import QtQuick

/**
 * Strategy for OpenAI-compatible chat completion APIs.
 * Covers OpenAI itself, Mistral, Ollama and other compatible endpoints.
 */
ApiStrategy {
    id: root

    property bool isReasoning: false
    property var pendingToolCalls: ({})  // Stream index -> { id, name, arguments }
    property string lastToolCallId: ""   // Pairs tool outputs back to their call

    function buildEndpoint(model: AiModel): string {
        return model.endpoint;
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePaths: var) {
        lastToolCallId = "";
        const baseData = {
            "model": model.model,
            "messages": [
                { role: "system", content: systemPrompt },
                ...messages.map((message, index) => buildMessageData(message, index)),
            ],
            "stream": true,
            "tools": tools,
            "temperature": temperature,
        };
        return model.extraParams ? Object.assign({}, baseData, model.extraParams) : baseData;
    }

    /**
     * Replays past function interactions using proper tool_calls/tool roles,
     * so multi-turn function calling keeps working on strict APIs.
     */
    function buildMessageData(message: AiMessageData, index: int): var {
        const hasFunctionOutput = message.functionName.length > 0 && message.functionResponse.length > 0;
        const hasFunctionCall = message.functionName.length > 0 && message.functionCall !== undefined;
        if (!hasFunctionOutput && !hasFunctionCall) {
            return { role: message.role, content: message.rawContent };
        }

        // Output messages carry no call object, so pair them with the
        // most recent call emitted while walking the history in order
        if (hasFunctionOutput) {
            return { role: "tool", tool_call_id: lastToolCallId, content: message.functionResponse };
        }

        // Only needs to be stable within a single request
        lastToolCallId = message.functionCall.id || `call_${index}`;
        return {
            role: "assistant",
            content: message.rawContent,
            tool_calls: [{
                id: lastToolCallId,
                type: "function",
                function: {
                    name: message.functionName,
                    arguments: JSON.stringify(message.functionCall.args ?? {}),
                },
            }],
        };
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
                console.log("[AI] Could not parse tool call arguments: ", e);
            }
        }

        message.rawContent += `\n\nFunction: ${call.name}(${call.arguments})\n`;
        message.functionName = call.name;
        message.functionCall = { name: call.name, args: args, id: call.id };
        return { functionCall: { name: call.name, args: args, id: call.id } };
    }

    function collectToolCallFragments(deltaToolCalls) {
        if (!deltaToolCalls || deltaToolCalls.length === 0) return;
        for (let i = 0; i < deltaToolCalls.length; i++) {
            const tc = deltaToolCalls[i];
            const idx = tc.index ?? 0;
            if (!pendingToolCalls[idx]) pendingToolCalls[idx] = { id: "", name: "", arguments: "" };
            if (tc.id) pendingToolCalls[idx].id = tc.id;
            if (tc.function?.name) pendingToolCalls[idx].name += tc.function.name;
            if (tc.function?.arguments) pendingToolCalls[idx].arguments += tc.function.arguments;
        }
    }

    function openReasoningBlock(message) {
        if (isReasoning) return;
        isReasoning = true;
        const block = "\n\n<think>\n\n";
        message.content += block;
        message.rawContent += block;
    }

    function closeReasoningBlock(message) {
        if (!isReasoning) return;
        isReasoning = false;
        const block = "\n\n</think>\n\n";
        message.content += block;
        message.rawContent += block;
    }

    function parseResponseLine(line, message) {
        let cleanData = line.trim();
        if (cleanData.startsWith("data:")) cleanData = cleanData.slice(5).trim();

        if (!cleanData || cleanData.startsWith(":")) return {};
        if (cleanData === "[DONE]") {
            const flushed = flushPendingToolCalls(message);
            if (flushed) flushed.finished = true;
            return flushed ?? { finished: true };
        }

        try {
            const dataJson = JSON.parse(cleanData);

            if (dataJson.error) {
                const errorMsg = `**Error**: ${dataJson.error.message || JSON.stringify(dataJson.error)}`;
                message.rawContent += errorMsg;
                message.content += errorMsg;
                return { finished: true };
            }

            const choice = dataJson.choices[0] ?? {};

            collectToolCallFragments(choice.delta?.tool_calls);

            const responseContent = choice.delta?.content || dataJson.message?.content;
            const responseReasoning = choice.delta?.reasoning || choice.delta?.reasoning_content;

            if (responseContent && responseContent.length > 0) {
                closeReasoningBlock(message);
                message.content += responseContent;
                message.rawContent += responseContent;
            } else if (responseReasoning && responseReasoning.length > 0) {
                openReasoningBlock(message);
                message.content += responseReasoning;
                message.rawContent += responseReasoning;
            }

            // "function_call" is the legacy variant still used by some providers
            if (choice.finish_reason === "tool_calls" || choice.finish_reason === "function_call") {
                const flushed = flushPendingToolCalls(message);
                if (flushed) return flushed;
            }

            if (dataJson.usage) {
                return {
                    tokenUsage: {
                        input: dataJson.usage.prompt_tokens ?? -1,
                        output: dataJson.usage.completion_tokens ?? -1,
                        total: dataJson.usage.total_tokens ?? -1,
                    }
                };
            }

            if (dataJson.done) {
                const flushed = flushPendingToolCalls(message);
                if (flushed) flushed.finished = true;
                return flushed ?? { finished: true };
            }
        } catch (e) {
            console.log("[AI] Could not parse line: ", e);
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
        lastToolCallId = "";
    }
}
