import QtQuick

ApiStrategy {
    property bool isReasoning: false
    // Streaming tool calls arrive as fragments across chunks; accumulate them
    property var pendingToolCalls: ({})  // index -> { id, name, arguments }

    function buildEndpoint(model: AiModel): string {
        // console.log("[AI] Endpoint: " + model.endpoint);
        return model.endpoint;
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePath: string) {
        let baseData = {
            "model": model.model,
            "messages": [
                {role: "system", content: systemPrompt},
                ...messages.map(message => {
                    return {
                        "role": message.role,
                        "content": message.rawContent,
                    }
                }),
            ],
            "stream": true,
            "tools": tools,
            "temperature": temperature,
        };
        return model.extraParams ? Object.assign({}, baseData, model.extraParams) : baseData;
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string): string {
        return `Authorization: Bearer \${${apiKeyEnvVarName}}`;
    }

    function flushPendingToolCalls(message) {
        const indices = Object.keys(pendingToolCalls);
        if (indices.length === 0) return null;
        const call = pendingToolCalls[indices[0]];
        pendingToolCalls = ({});

        let args = {};
        if (call.arguments && call.arguments.length > 0) {
            try {
                args = JSON.parse(call.arguments);
            } catch (e) {
                console.log("[AI] OpenAI: Could not parse tool call arguments: ", e);
            }
        }

        const newContent = `\n\nFunction: ${call.name}(${call.arguments})\n`;
        message.rawContent += newContent;

        message.functionName = call.name;
        message.functionCall = { name: call.name, args: args, id: call.id };
        return { functionCall: { name: call.name, args: args, id: call.id } };
    }

    function parseResponseLine(line, message) {
        // Remove 'data: ' prefix if present and trim whitespace
        let cleanData = line.trim();
        if (cleanData.startsWith("data:")) {
            cleanData = cleanData.slice(5).trim();
        }

        // console.log("[AI] OpenAI: Data:", cleanData);

        // Handle special cases
        if (!cleanData || cleanData.startsWith(":")) return {};
        if (cleanData === "[DONE]") {
            // Stream may end without an explicit tool_calls finish reason
            const flushed = flushPendingToolCalls(message);
            if (flushed) {
                flushed.finished = true;
                return flushed;
            }
            return { finished: true };
        }

        // Real stuff
        try {
            const dataJson = JSON.parse(cleanData);

            // Error response handling
            if (dataJson.error) {
                const errorMsg = `**Error**: ${dataJson.error.message || JSON.stringify(dataJson.error)}`;
                message.rawContent += errorMsg;
                message.content += errorMsg;
                return { finished: true };
            }

            let newContent = "";

            const responseContent = dataJson.choices[0]?.delta?.content || dataJson.message?.content;
            const responseReasoning = dataJson.choices[0]?.delta?.reasoning || dataJson.choices[0]?.delta?.reasoning_content;
            const deltaToolCalls = dataJson.choices[0]?.delta?.tool_calls;
            const finishReason = dataJson.choices[0]?.finish_reason;

            // Accumulate streamed tool call fragments
            if (deltaToolCalls && deltaToolCalls.length > 0) {
                for (let i = 0; i < deltaToolCalls.length; i++) {
                    const tc = deltaToolCalls[i];
                    const idx = tc.index ?? 0;
                    if (!pendingToolCalls[idx]) pendingToolCalls[idx] = { id: "", name: "", arguments: "" };
                    if (tc.id) pendingToolCalls[idx].id = tc.id;
                    const fnName = tc.function?.name;
                    if (fnName) pendingToolCalls[idx].name += fnName;
                    const argsFragment = tc.function?.arguments;
                    if (argsFragment) pendingToolCalls[idx].arguments += argsFragment;
                }
            }

            if (responseContent && responseContent.length > 0) {
                if (isReasoning) {
                    isReasoning = false;
                    const endBlock = "\n\n</think>\n\n";
                    message.content += endBlock;
                    message.rawContent += endBlock;
                }
                newContent = responseContent;
            } else if (responseReasoning && responseReasoning.length > 0) {
                if (!isReasoning) {
                    isReasoning = true;
                    const startBlock = "\n\n<think>\n\n";
                    message.rawContent += startBlock;
                    message.content += startBlock;
                }
                newContent = responseReasoning;
            }

            if (newContent.length > 0) {
                message.content += newContent;
                message.rawContent += newContent;
            }

            // Emit the completed tool call once the model finishes the turn
            if (finishReason === "tool_calls") {
                const flushed = flushPendingToolCalls(message);
                if (flushed) return flushed;
            }

            // Usage metadata
            if (dataJson.usage) {
                return {
                    tokenUsage: {
                        input: dataJson.usage.prompt_tokens ?? -1,
                        output: dataJson.usage.completion_tokens ?? -1,
                        total: dataJson.usage.total_tokens ?? -1
                    }
                };
            }

            if (dataJson.done) {
                const flushed = flushPendingToolCalls(message);
                if (flushed) {
                    flushed.finished = true;
                    return flushed;
                }
                return { finished: true };
            }

        } catch (e) {
            console.log("[AI] OpenAI: Could not parse line: ", e);
        }

        return {};
    }

    function onRequestFinished(message) {
        // Flush any tool call that completed right at stream end
        return flushPendingToolCalls(message) ?? {};
    }

    function reset() {
        isReasoning = false;
        pendingToolCalls = ({});
    }
}
