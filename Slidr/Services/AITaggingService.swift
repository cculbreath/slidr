import Foundation
import OSLog
import SwiftOpenAI

struct AITagResult: Sendable {
    let tags: [String]
    let summary: String
    let productionSource: String
    let confidence: Double
}

@MainActor
@Observable
final class AITaggingService {
    private static let logger = Logger(subsystem: "com.physicscloud.slidr", category: "AITagging")
    private let contactSheetGenerator = ContactSheetGenerator()

    // MARK: - Single-Pass: Images & GIFs

    func tagImage(imageData: Data, existingTags: [String]?, tagMode: AITagMode, model: String, apiKey: String) async throws -> AITagResult {
        Self.logger.info("tagImage: model=\(model), imageSize=\(imageData.count / 1024)KB, tagMode=\(tagMode.rawValue)")
        let service = OpenAIServiceFactory.service(apiKey: apiKey, overrideBaseURL: "https://api.x.ai")

        let base64Image = imageData.base64EncodedString()
        let systemPrompt = buildSystemPrompt(tagMode: tagMode, existingTags: existingTags, transcript: nil)

        let schema = buildResponseSchema(tagMode: tagMode, existingTags: existingTags)
        let responseFormat = JSONSchemaResponseFormat(name: "tag_result", strict: true, schema: schema)

        let parameters = ChatCompletionParameters(
            messages: [
                .init(role: .system, content: .text(systemPrompt)),
                .init(role: .user, content: .contentArray([
                    .text("Analyze this media and provide tags, summary, and production classification."),
                    .imageUrl(.init(url: URL(string: "data:image/jpeg;base64,\(base64Image)")!)),
                ])),
            ],
            model: .custom(model),
            responseFormat: .jsonSchema(responseFormat)
        )

        Self.logger.debug("tagImage: sending request to xAI API...")
        let result: ChatCompletionObject
        do {
            result = try await service.startChat(parameters: parameters)
        } catch {
            Self.logger.error("tagImage API call failed: \(Self.describeAPIError(error))")
            throw error
        }
        Self.logger.info("tagImage: response received, choices=\(result.choices?.count ?? 0)")

        guard let content = result.choices?.first?.message?.content else {
            throw AITaggingError.emptyResponse
        }

        return try parseTagResult(content)
    }

    // MARK: - Multi-Turn: Videos

    func tagVideo(videoURL: URL, transcript: String?, existingTags: [String]?, tagMode: AITagMode, model: String, apiKey: String) async throws -> AITagResult {
        Self.logger.info("tagVideo: model=\(model), url=\(videoURL.lastPathComponent), tagMode=\(tagMode.rawValue)")
        let service = OpenAIServiceFactory.service(apiKey: apiKey, overrideBaseURL: "https://api.x.ai")

        // Generate overview contact sheet
        Self.logger.debug("tagVideo: generating contact sheet...")
        guard let overviewData = try await contactSheetGenerator.generateOverviewSheet(from: videoURL, mediaType: .video) else {
            throw AITaggingError.contactSheetFailed
        }
        Self.logger.info("tagVideo: contact sheet generated (\(overviewData.count / 1024)KB)")

        let base64Overview = overviewData.base64EncodedString()
        let systemPrompt = buildSystemPrompt(tagMode: tagMode, existingTags: existingTags, transcript: transcript)
        let tools = buildVideoTools()

        var messages: [ChatCompletionParameters.Message] = [
            .init(role: .system, content: .text(systemPrompt)),
            .init(role: .user, content: .contentArray([
                .text("Analyze this video contact sheet. Each thumbnail represents an evenly-spaced frame. You have tools to zoom into frame ranges or view individual frames at higher resolution. When done analyzing, call submit_tags."),
                .imageUrl(.init(url: URL(string: "data:image/jpeg;base64,\(base64Overview)")!)),
            ])),
        ]

        var zoomBudget = 4
        let maxTurns = 8

        for turn in 0..<maxTurns {
            Self.logger.debug("tagVideo: turn \(turn + 1)/\(maxTurns), sending request...")
            let parameters = ChatCompletionParameters(
                messages: messages,
                model: .custom(model),
                tools: tools
            )

            let result: ChatCompletionObject
            do {
                result = try await service.startChat(parameters: parameters)
            } catch {
                Self.logger.error("tagVideo API call failed on turn \(turn + 1): \(Self.describeAPIError(error))")
                throw error
            }
            guard let choice = result.choices?.first else {
                throw AITaggingError.emptyResponse
            }

            guard let assistantMessage = choice.message else {
                throw AITaggingError.emptyResponse
            }

            // Check for tool calls
            if let toolCalls = assistantMessage.toolCalls, !toolCalls.isEmpty {
                messages.append(.init(role: .assistant, content: .text(assistantMessage.content ?? ""), toolCalls: toolCalls))

                for toolCall in toolCalls {
                    guard let functionName = toolCall.function.name else { continue }
                    let arguments = toolCall.function.arguments ?? "{}"

                    if functionName == "submit_tags" {
                        return try parseSubmitTagsArguments(arguments)
                    }

                    if zoomBudget <= 0 {
                        messages.append(.init(role: .tool, content: .text("Zoom budget exhausted. Please call submit_tags now with your analysis."), toolCallID: toolCall.id))
                        continue
                    }

                    let toolResult = try await handleToolCall(functionName: functionName, arguments: arguments, videoURL: videoURL)
                    zoomBudget -= 1

                    if let imageData = toolResult.imageData {
                        let base64 = imageData.base64EncodedString()
                        messages.append(.init(role: .tool, content: .contentArray([
                            .text(toolResult.text),
                            .imageUrl(.init(url: URL(string: "data:image/jpeg;base64,\(base64)")!)),
                        ]), toolCallID: toolCall.id))
                    } else {
                        messages.append(.init(role: .tool, content: .text(toolResult.text), toolCallID: toolCall.id))
                    }
                }
            } else {
                // Text-only response; nudge to call submit_tags
                messages.append(.init(role: .assistant, content: .text(assistantMessage.content ?? "")))

                if turn >= maxTurns - 2 {
                    messages.append(.init(role: .user, content: .text("Please call submit_tags now with your analysis.")))
                } else {
                    messages.append(.init(role: .user, content: .text("Use your tools to analyze further, or call submit_tags when ready.")))
                }
            }
        }

        // Fallback: force a final structured response
        Self.logger.warning("Multi-turn loop exhausted without submit_tags call, requesting final answer")
        let schema = buildResponseSchema(tagMode: tagMode, existingTags: existingTags)
        let responseFormat = JSONSchemaResponseFormat(name: "tag_result", strict: true, schema: schema)
        messages.append(.init(role: .user, content: .text("Please provide your final analysis as JSON.")))

        let finalParams = ChatCompletionParameters(
            messages: messages,
            model: .custom(model),
            responseFormat: .jsonSchema(responseFormat)
        )

        let finalResult = try await service.startChat(parameters: finalParams)
        guard let content = finalResult.choices?.first?.message?.content else {
            throw AITaggingError.emptyResponse
        }

        return try parseTagResult(content)
    }

    // MARK: - Summary-Only

    func summarize(imageData: Data, model: String, apiKey: String) async throws -> String {
        Self.logger.info("summarize: model=\(model), imageSize=\(imageData.count / 1024)KB")
        let service = OpenAIServiceFactory.service(apiKey: apiKey, overrideBaseURL: "https://api.x.ai")
        let base64 = imageData.base64EncodedString()

        let parameters = ChatCompletionParameters(
            messages: [
                .init(role: .system, content: .text("You are a media analyst. Provide a concise 2-3 sentence description of the visual content.")),
                .init(role: .user, content: .contentArray([
                    .text("Describe this media."),
                    .imageUrl(.init(url: URL(string: "data:image/jpeg;base64,\(base64)")!)),
                ])),
            ],
            model: .custom(model)
        )

        Self.logger.debug("summarize: sending request to xAI API...")
        let result: ChatCompletionObject
        do {
            result = try await service.startChat(parameters: parameters)
        } catch {
            Self.logger.error("summarize API call failed: \(Self.describeAPIError(error))")
            throw error
        }
        guard let content = result.choices?.first?.message?.content else {
            throw AITaggingError.emptyResponse
        }

        return content
    }

    // MARK: - Error Helpers

    static func describeAPIError(_ error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.displayDescription
        }
        if let localizedError = error as? LocalizedError, let desc = localizedError.errorDescription {
            return desc
        }
        let desc = error.localizedDescription
        if desc.contains("The operation could") || desc.contains("The operation couldn") {
            return String(describing: error)
        }
        return desc
    }

    // MARK: - Prompt Building

    private func buildSystemPrompt(tagMode: AITagMode, existingTags: [String]?, transcript: String?) -> String {
        var prompt = """
        You are a media content analyst. Analyze the provided media and generate:
        1. Descriptive tags (15-30 tags) covering subjects, actions, mood, setting, style, and notable details
        2. A concise 2-3 sentence summary of the content
        3. Production source classification: "studio" (professional production), "creator" (content creator/influencer), "homemade" (amateur/personal), or "unknown"
        4. A confidence score (0.0-1.0) for your analysis
        """

        if tagMode == .constrainToExisting, let existing = existingTags, !existing.isEmpty {
            prompt += "\n\nIMPORTANT: You must ONLY select tags from this list: \(existing.joined(separator: ", ")). Do not invent new tags."
        }

        if let transcript = transcript, !transcript.isEmpty {
            prompt += "\n\nAudio transcript for additional context:\n\(transcript)"
        }

        return prompt
    }

    private func buildResponseSchema(tagMode: AITagMode, existingTags: [String]?) -> JSONSchema {
        let tagsSchema: JSONSchema
        if tagMode == .constrainToExisting, let existing = existingTags, !existing.isEmpty {
            tagsSchema = .init(type: .array, items: .init(type: .string, enum: existing.map { .init($0) }))
        } else {
            tagsSchema = .init(type: .array, items: .init(type: .string))
        }

        return .init(
            type: .object,
            properties: [
                "tags": tagsSchema,
                "summary": .init(type: .string),
                "production_source": .init(type: .string, enum: ["studio", "creator", "homemade", "unknown"].map { .init($0) }),
                "confidence": .init(type: .number),
            ],
            required: ["tags", "summary", "production_source", "confidence"],
            additionalProperties: false
        )
    }

    // MARK: - Tool Definitions

    private func buildVideoTools() -> [ChatCompletionParameters.Tool] {
        [
            .init(function: .init(
                name: "range_zoom",
                strict: nil,
                description: "Zoom into a range of thumbnails for higher resolution. Provide start and end thumbnail numbers (1-indexed from the overview).",
                parameters: .init(
                    type: .object,
                    properties: [
                        "start_thumb": .init(type: .integer, description: "Start thumbnail number (1-indexed)"),
                        "end_thumb": .init(type: .integer, description: "End thumbnail number (1-indexed)"),
                    ],
                    required: ["start_thumb", "end_thumb"]
                )
            )),
            .init(function: .init(
                name: "view_frame",
                strict: nil,
                description: "View a single frame at maximum resolution. Provide the thumbnail number from the overview.",
                parameters: .init(
                    type: .object,
                    properties: [
                        "frame_num": .init(type: .integer, description: "Thumbnail number to view (1-indexed)"),
                    ],
                    required: ["frame_num"]
                )
            )),
            .init(function: .init(
                name: "submit_tags",
                strict: nil,
                description: "Submit your final analysis with tags, summary, production source, and confidence.",
                parameters: .init(
                    type: .object,
                    properties: [
                        "tags": .init(type: .array, items: .init(type: .string)),
                        "summary": .init(type: .string),
                        "production_source": .init(type: .string, enum: ["studio", "creator", "homemade", "unknown"].map { .init($0) }),
                        "confidence": .init(type: .number),
                    ],
                    required: ["tags", "summary", "production_source", "confidence"]
                )
            )),
        ]
    }

    // MARK: - Tool Call Handling

    private struct ToolCallResult {
        let text: String
        let imageData: Data?
    }

    private func handleToolCall(functionName: String, arguments: String, videoURL: URL) async throws -> ToolCallResult {
        guard let argData = arguments.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: argData) as? [String: Any] else {
            return ToolCallResult(text: "Invalid arguments", imageData: nil)
        }

        let totalThumbs = 20

        switch functionName {
        case "range_zoom":
            let start = (args["start_thumb"] as? Int ?? 1) - 1
            let end = args["end_thumb"] as? Int ?? totalThumbs
            let startFraction = Double(max(start, 0)) / Double(totalThumbs)
            let endFraction = Double(min(end, totalThumbs)) / Double(totalThumbs)

            let data = try await contactSheetGenerator.generateZoomSheet(from: videoURL, startFraction: startFraction, endFraction: endFraction)
            return ToolCallResult(text: "Zoomed into frames \(start + 1)-\(end) at higher resolution.", imageData: data)

        case "view_frame":
            let frameNum = (args["frame_num"] as? Int ?? 1) - 1
            let fraction = Double(max(frameNum, 0)) / Double(totalThumbs)

            let data = try await contactSheetGenerator.generateSingleFrameData(from: videoURL, atFraction: fraction)
            return ToolCallResult(text: "Single frame at position \(frameNum + 1)/\(totalThumbs) at full resolution.", imageData: data)

        default:
            return ToolCallResult(text: "Unknown tool", imageData: nil)
        }
    }

    // MARK: - Response Parsing

    private func parseTagResult(_ content: String) throws -> AITagResult {
        guard let data = content.data(using: .utf8) else {
            throw AITaggingError.invalidJSON
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AITaggingError.invalidJSON
        }

        let tags = (json["tags"] as? [String]) ?? []
        let summary = (json["summary"] as? String) ?? ""
        let productionSource = (json["production_source"] as? String) ?? "unknown"
        let confidence = (json["confidence"] as? Double) ?? 0.0

        return AITagResult(tags: tags, summary: summary, productionSource: productionSource, confidence: confidence)
    }

    private func parseSubmitTagsArguments(_ arguments: String) throws -> AITagResult {
        guard let data = arguments.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AITaggingError.invalidJSON
        }

        let tags = (json["tags"] as? [String]) ?? []
        let summary = (json["summary"] as? String) ?? ""
        let productionSource = (json["production_source"] as? String) ?? "unknown"
        let confidence = (json["confidence"] as? Double) ?? 0.0

        return AITagResult(tags: tags, summary: summary, productionSource: productionSource, confidence: confidence)
    }
}

// MARK: - Errors

enum AITaggingError: LocalizedError {
    case emptyResponse
    case contactSheetFailed
    case invalidJSON
    case noAPIKey

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "AI service returned an empty response"
        case .contactSheetFailed:
            return "Failed to generate contact sheet for analysis"
        case .invalidJSON:
            return "Failed to parse AI response"
        case .noAPIKey:
            return "No xAI API key configured"
        }
    }
}
