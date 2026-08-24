import QtQuick
import qs.modules.common.functions as CF

ApiStrategy {
    readonly property string apiKeyEnvVarName: "API_KEY"
    readonly property string fileUploadAuthHeader: `x-goog-api-key: \${${apiKeyEnvVarName}}`
    readonly property string fileUriVarName: "file_uri"
    readonly property string fileMimeTypeVarName: "MIME_TYPE"
    readonly property string fileUriSubstitutionString: "{{ " + fileUriVarName + " }}"
    readonly property string fileMimeTypeSubstitutionString: "{{ " + fileMimeTypeVarName + " }}"
    property string buffer: ""
    
    function buildEndpoint(model: AiModel): string {
        return model.endpoint;
    }

    function isGemmaModel(model: AiModel): bool {
        return model.model.toLowerCase().startsWith("gemma");
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePaths: var) {
        const paths = (typeof filePaths === "string") ? (filePaths.length > 0 ? [filePaths] : []) : (filePaths && filePaths.length > 0 ? filePaths : []);

        let contents = messages.map(message => {
            const geminiApiRoleName = (message.role === "assistant") ? "model" : message.role;
            const usingSearch = tools && tools.length > 0 && tools[0]?.google_search !== undefined;
            if (!usingSearch && message.functionCall != undefined && message.functionName && message.functionName.length > 0) {
                return {
                    "role": geminiApiRoleName,
                    "parts": [{
                        functionCall: {
                            "name": message.functionName,
                            "args": message.functionCall?.args ?? {}
                        }
                    }]
                }
            }
            if (!usingSearch && message.functionResponse != undefined && message.functionName && message.functionName.length > 0) {
                return {
                    "role": geminiApiRoleName,
                    "parts": [{ 
                        functionResponse: {
                            "name": message.functionName,
                            "response": { "output": message.functionResponse }
                        }
                    }]
                }
            }
            return {
                "role": geminiApiRoleName,
                "parts": [
                    { text: message.rawContent },
                    ...(message.fileInfos && message.fileInfos.length > 0 ? message.fileInfos.map(info => ({ 
                        "file_data": {
                            "mime_type": info.mimeType,
                            "file_uri": info.uri
                        }
                    })) : [])
                ]
            }
        })
        if (paths && paths.length > 0) {
            for (let i = 0; i < paths.length; i++) {
                contents[contents.length - 1].parts.unshift({
                    file_data: {
                        mime_type: fileMimeTypeSubstitutionString + i,
                        file_uri: fileUriSubstitutionString + i
                    }
                });
            }
        }

        let generationConfig = {
            "temperature": temperature,
            "topP": 0.95,
            "topK": 64,
            "candidateCount": 1,
        };

        let baseData = {
            "contents": contents,
            "generationConfig": generationConfig,
            "safetySettings": [
                {
                    "category": "HARM_CATEGORY_HATE_SPEECH",
                    "threshold": "OFF"
                },
                {
                    "category": "HARM_CATEGORY_HARASSMENT",
                    "threshold": "OFF"
                },
                {
                    "category": "HARM_CATEGORY_SEXUALLY_EXPLICIT",
                    "threshold": "OFF"
                },
                {
                    "category": "HARM_CATEGORY_DANGEROUS_CONTENT",
                    "threshold": "OFF"
                }
            ]
        };

        if (tools && tools.length > 0) {
            baseData["tools"] = tools;
        }

        if (systemPrompt && systemPrompt.trim().length > 0) {
            baseData["system_instruction"] = {
                "parts": [{ text: systemPrompt }]
            };
        }

        return model.extraParams ? Object.assign({}, baseData, model.extraParams) : baseData;
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string): string {
        return `x-goog-api-key: \${${apiKeyEnvVarName}}`;
    }

    function parseResponseLine(line, message) {
        if (line.startsWith("[")) {
            buffer += line.slice(1).trim();
        } else if (line === "]") {
            buffer += line.slice(0, -1).trim();
            return parseBuffer(message);
        } else if (line.startsWith(",")) {
            return parseBuffer(message);
        } else {
            buffer += line.trim();
        }
        return {};
    }

    function parseBuffer(message) {
        // console.log("[Ai] Gemini buffer: ", buffer);
        let finished = false;
        let parsed = false;
        try {
            if (buffer.length === 0) return {};
            const dataJson = JSON.parse(buffer);
            parsed = true;

            // Uploaded file
            if (dataJson.uploadedFile) {
                const info = dataJson.uploadedFile;
                let newFileInfos = message.fileInfos ? [...message.fileInfos] : [];
                newFileInfos[info.index] = { uri: info.uri, mimeType: info.mimeType, localPath: info.localPath };
                message.fileInfos = newFileInfos;
                return ({})
            }

            // Error response handling
            if (dataJson.error) {
                const errorMsg = `**Error ${dataJson.error.code}**: ${dataJson.error.message}`;
                message.rawContent += errorMsg;
                message.content += errorMsg;
                return { finished: true };
            }

            // No candidates?
            if (!dataJson.candidates) return {};
            
            // Finished?
            if (dataJson.candidates[0]?.finishReason) {
                finished = true;
            }
            
            // Function call handling
            const parts = dataJson.candidates[0]?.content?.parts ?? [];
            const funcCallPart = parts.find(p => p && p.functionCall);
            if (funcCallPart && funcCallPart.functionCall) {
                const functionCall = funcCallPart.functionCall;
                message.functionName = functionCall.name;
                message.functionCall = functionCall; 

                const showSearchModeLabel = false;

                const functionLabels = {
                    "switch_to_search_mode": "Search Mode",
                };

                const displayLabel = functionLabels[functionCall.name] ?? functionCall.name;
                const rawNewContent = `\n\nFunction: ${functionCall.name}(${JSON.stringify(functionCall.args, null, 2)})\n`;
                const displayNewContent = `\n\n${displayLabel}\n`;

                message.rawContent += rawNewContent;
                if (showSearchModeLabel) {
                    message.content += displayNewContent;
                }
                message.visibleToUser = showSearchModeLabel || message.content.trim().length > 0;

                return { functionCall: { name: functionCall.name, args: functionCall.args }, finished: finished };
            }
            let responseContent = "";
            for (let i = 0; i < parts.length; i++) {
                const part = parts[i];
                // Skip parts flagged as internal thinking
                if (part.thought === true) continue;
                if (part.text !== undefined) {
                    responseContent += part.text;
                }
            }
            message.rawContent += responseContent;
            message.content += responseContent;
            
            // Handle annotations and metadata
            const annotationSources = dataJson.candidates[0]?.groundingMetadata?.groundingChunks?.map(chunk => {
                return {
                    "type": "url_citation",
                    "text": chunk?.web?.title,
                    "url": chunk?.web?.uri,
                }
            }) ?? [];

            const annotations = dataJson.candidates[0]?.groundingMetadata?.groundingSupports?.map(citation => {
                return {
                    "type": "url_citation",
                    "start_index": citation.segment?.startIndex,
                    "end_index": citation.segment?.endIndex,
                    "text": citation?.segment.text,
                    "url": annotationSources[citation.groundingChunkIndices[0]]?.url,
                    "sources": citation.groundingChunkIndices
                }
            });
            message.annotationSources = annotationSources;
            message.annotations = annotations;
            message.searchQueries = dataJson.candidates[0]?.groundingMetadata?.webSearchQueries ?? [];

            // Usage metadata
            if (dataJson.usageMetadata) {
                return {
                    tokenUsage: {
                        input: dataJson.usageMetadata.promptTokenCount ?? -1,
                        output: dataJson.usageMetadata.candidatesTokenCount ?? -1,
                        total: dataJson.usageMetadata.totalTokenCount ?? -1
                    },
                    finished: finished
                };
            }
            
        } catch (e) {
            console.log("[AI] Gemini: Could not parse buffer: ", e);
            if (buffer.length > 1000000) parsed = true;
        } finally {
            if (parsed) buffer = "";
        }
        return { finished: finished };
    }

    function onRequestFinished(message) {
        return parseBuffer(message);
    }
    
    function reset() {
        buffer = "";
    }

    function buildScriptFileSetup(filePaths: var): string {
        const paths = (typeof filePaths === "string") ? (filePaths.length > 0 ? [filePaths] : []) : (Array.isArray(filePaths) ? filePaths : []);
        let content = ""

        content += `ai_gs_auth_file=$(mktemp)\n`;
        content += `if [[ -z "$ai_gs_auth_file" ]]; then exit 1; fi\n`;
        content += `trap 'rm -f "\${ai_auth_header_file:-}" "$ai_gs_auth_file"' EXIT\n`;
        content += `printf '%s\\n' "${fileUploadAuthHeader}" > "$ai_gs_auth_file"\n`;

        for (let i = 0; i < paths.length; i++) {
            const trimmedFilePath = CF.FileUtils.trimFileProtocol(paths[i]);
            const mimeVar = `${fileMimeTypeVarName}${i}`;
            const uriVar = `${fileUriVarName}${i}`;

            content += `IMAGE_PATH_${i}='${CF.StringUtils.shellSingleQuoteEscape(trimmedFilePath)}'\n`;
            content += `${mimeVar}=$(file -b --mime-type "$IMAGE_PATH_${i}")\n`;
            content += `if [[ "$${mimeVar}" == text/* ]] || [[ "$${mimeVar}" == inode/x-empty ]] || [[ "$${mimeVar}" == application/x-shellscript ]]; then\n`;
            content += `    ${mimeVar}="text/plain"\n`;
            content += `fi\n`;
            content += `NUM_BYTES_${i}=$(wc -c < "$IMAGE_PATH_${i}")\n`;
            content += `tmp_header_file_${i}=$(mktemp)\n`;
            content += `tmp_file_info_file_${i}=$(mktemp)\n`;

            content += 'curl "https://generativelanguage.googleapis.com/upload/v1beta/files"'
                + ` -H "@$ai_gs_auth_file"`
                + ` -D $tmp_header_file_${i}`
                + ' -H "X-Goog-Upload-Protocol: resumable"'
                + ' -H "X-Goog-Upload-Command: start"'
                + ` -H "X-Goog-Upload-Header-Content-Length: \${NUM_BYTES_${i}}"`
                + ` -H "X-Goog-Upload-Header-Content-Type: \${${mimeVar}}"`
                + ' -H "Content-Type: application/json"'
                + ` -d "{'file': {'display_name': 'Image'}}" 2> /dev/null`
                + '\n';

            content += `upload_url_${i}=$(grep -i "x-goog-upload-url: " "\${tmp_header_file_${i}}" | cut -d" " -f2 | tr -d "\r")\n`;
            content += `rm -f "\${tmp_header_file_${i}}"\n`;

            content += `curl "\${upload_url_${i}}"`
                + ` -H "@$ai_gs_auth_file"`
                + ` -H "Content-Length: \${NUM_BYTES_${i}}"`
                + ' -H "X-Goog-Upload-Offset: 0"'
                + ' -H "X-Goog-Upload-Command: upload, finalize"'
                + ` --data-binary "@$IMAGE_PATH_${i}" 2> /dev/null > "\${tmp_file_info_file_${i}}"\n`;

            content += `${uriVar}=$(jq -r ".file.uri" "$tmp_file_info_file_${i}")\n`
            content += `rm -f "\${tmp_file_info_file_${i}}"\n`;
            content += `printf "{\\"uploadedFile\\": {\\"uri\\": \\"$${uriVar}\\", \\"mimeType\\": \\"$${mimeVar}\\", \\"localPath\\": \\"$IMAGE_PATH_${i}\\", \\"index\\": ${i}}}\\n,\\n"\n`
        }

        return content
    }

    function finalizeScriptContent(scriptContent: string, filePathsCount: var): string {
        let count = 0;
        if (typeof filePathsCount === "number") {
            count = filePathsCount;
        } else if (typeof filePathsCount === "string") {
            count = filePathsCount.length > 0 ? 1 : 0;
        } else if (Array.isArray(filePathsCount)) {
            count = filePathsCount.length;
        }
        let res = scriptContent;
        for (let i = 0; i < count; i++) {
            res = res.replace(fileMimeTypeSubstitutionString + i, `'"\$${fileMimeTypeVarName}${i}"'`)
                     .replace(fileUriSubstitutionString + i, `'"\$${fileUriVarName}${i}"'`);
        }
        return res;
    }
}
