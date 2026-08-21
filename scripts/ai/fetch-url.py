#!/usr/bin/env python3
import sys
import os
import re
import json
import html
import socket
import ipaddress
import urllib.request
import urllib.error
import urllib.parse
import gzip
import zlib

MAX_CHARS = 2500

def is_safe_url(url: str) -> tuple[bool, str]:
    """Validates the URL to prevent SSRF and access to local/private networks."""
    try:
        parsed = urllib.parse.urlparse(url)
        if parsed.scheme not in ("http", "https"):
            return False, f"Unsupported scheme '{parsed.scheme}'. Only http and https are allowed."

        hostname = parsed.hostname
        if not hostname:
            return False, "Missing hostname in URL."

        # Block localhost strings explicitly
        if hostname.lower() in ("localhost", "localhost.localdomain", "broadcasthost"):
            return False, "Access to localhost is blocked for security (SSRF prevention)."

        # Resolve hostname to IP addresses and check for private/local ranges
        addr_info = socket.getaddrinfo(hostname, None)
        for family, socktype, proto, canonname, sockaddr in addr_info:
            ip_str = sockaddr[0]
            ip = ipaddress.ip_address(ip_str)
            if (
                ip.is_private
                or ip.is_loopback
                or ip.is_link_local
                or ip.is_reserved
                or ip.is_multicast
                or ip.is_unspecified
            ):
                return False, f"Access to private/internal network ({ip_str}) is blocked for security (SSRF prevention)."

            # Block cloud metadata IP explicitly
            if ip_str == "169.254.169.254":
                return False, "Access to cloud metadata endpoints is blocked."

        return True, ""
    except socket.gaierror as e:
        return False, f"DNS resolution failed for '{parsed.hostname}': {e}"
    except Exception as e:
        return False, f"URL validation error: {e}"

def apply_truncation(text: str, max_chars: int = MAX_CHARS) -> str:
    """Appends an explicit truncation indicator if the content was truncated."""
    if len(text) > max_chars:
        return text[:max_chars].rstrip() + f"\n\n[Content truncated at {max_chars} characters]"
    return text

def extract_main_html(raw_html: str) -> str:
    """Extracts main textual content, prioritizing <article> or <main> and stripping boilerplate."""
    # 1. Remove non-content structural elements and assets
    cleaned_html = re.sub(
        r"<(script|style|noscript|svg|iframe|header|footer|nav|aside|form)[^>]*>.*?</\1>",
        " ",
        raw_html,
        flags=re.DOTALL | re.IGNORECASE,
    )
    # Remove HTML comments
    cleaned_html = re.sub(r"<!--.*?-->", " ", cleaned_html, flags=re.DOTALL)

    # 2. Heuristic: Prioritize <article> or <main> container if present
    article_match = re.search(r"<(article|main)[^>]*>(.*?)</\1>", cleaned_html, flags=re.DOTALL | re.IGNORECASE)
    if article_match:
        content_html = article_match.group(2)
    else:
        # Check for role="main" or common main content IDs
        role_main_match = re.search(
            r"<[^>]+(?:role=[\"']main[\"']|id=[\"'](?:content|main|main-content)[\"'])[^>]*>(.*?)</(?:div|section|main|article)>",
            cleaned_html,
            flags=re.DOTALL | re.IGNORECASE,
        )
        if role_main_match:
            content_html = role_main_match.group(1)
        else:
            body_match = re.search(r"<body[^>]*>(.*?)</body>", cleaned_html, flags=re.DOTALL | re.IGNORECASE)
            content_html = body_match.group(1) if body_match else cleaned_html

    # 3. Convert block/breaks to newlines
    text = re.sub(r"<(h[1-6]|p|div|section|article|li|tr|br)[^>]*>", "\n", content_html, flags=re.IGNORECASE)
    # 4. Strip remaining HTML tags
    text = re.sub(r"<[^>]+>", " ", text)
    # 5. Unescape HTML entities
    text = html.unescape(text)
    # 6. Normalize lines and whitespace
    lines = [re.sub(r"[ \t]+", " ", line).strip() for line in text.splitlines()]
    text = "\n".join(line for line in lines if line)
    return text

def fetch_url(url: str) -> str:
    url = url.strip()
    if not url.startswith("http://") and not url.startswith("https://"):
        url = "https://" + url

    # 1. SSRF Protection check
    is_safe, error_msg = is_safe_url(url)
    if not is_safe:
        return f"Security Error: {error_msg}"

    headers = {
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Encoding": "gzip, deflate",
    }

    # Specialized handler for GitHub repositories
    gh_match = re.match(r"^https?://github\.com/([^/]+)/([^/]+)/?$", url)
    if gh_match:
        owner, repo = gh_match.groups()
        if repo.endswith(".git"):
            repo = repo[:-4]
        api_url = f"https://api.github.com/repos/{owner}/{repo}"
        gh_headers = {"User-Agent": "QuickShell-AI"}
        gh_token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
        if gh_token:
            gh_headers["Authorization"] = f"Bearer {gh_token}"

        try:
            req = urllib.request.Request(api_url, headers=gh_headers)
            with urllib.request.urlopen(req, timeout=8) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                desc = data.get("description") or "No description provided."
                lang = data.get("language") or "Not specified"
                stars = data.get("stargazers_count", 0)
                branch = data.get("default_branch", "main")

                readme_content = ""
                for branch_name in [branch, "main", "master"]:
                    try:
                        readme_url = f"https://raw.githubusercontent.com/{owner}/{repo}/{branch_name}/README.md"
                        with urllib.request.urlopen(urllib.request.Request(readme_url, headers=headers), timeout=5) as r_resp:
                            r_bytes = r_resp.read()
                            r_encoding = r_resp.headers.get("Content-Encoding", "").lower()
                            if "gzip" in r_encoding:
                                r_bytes = gzip.decompress(r_bytes)
                            elif "deflate" in r_encoding:
                                r_bytes = zlib.decompress(r_bytes)
                            readme_content = r_bytes.decode("utf-8", errors="ignore")[:2000]
                            if readme_content:
                                break
                    except Exception:
                        continue

                result = f"GitHub Repository: {owner}/{repo}\nDescription: {desc}\nLanguage: {lang}\nStars: {stars}\n"
                if readme_content:
                    result += f"\n--- README.md ---\n{readme_content}"
                return apply_truncation(result)
        except Exception:
            pass  # Fallback to standard web fetch if GitHub API fails

    # Standard web page fetch
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=10) as resp:
            content_type = resp.headers.get("Content-Type", "").lower()
            content_encoding = resp.headers.get("Content-Encoding", "").lower()
            raw_bytes = resp.read(300000)  # Read at most 300KB

            # Handle gzip / deflate decompression
            if "gzip" in content_encoding:
                try:
                    raw_bytes = gzip.decompress(raw_bytes)
                except Exception:
                    pass
            elif "deflate" in content_encoding:
                try:
                    raw_bytes = zlib.decompress(raw_bytes)
                except Exception:
                    pass

            charset = resp.headers.get_content_charset() or "utf-8"
            raw_text = raw_bytes.decode(charset, errors="ignore")

            if "json" in content_type:
                try:
                    parsed = json.loads(raw_text)
                    return apply_truncation(json.dumps(parsed, indent=2))
                except Exception:
                    return apply_truncation(raw_text)

            if "html" in content_type or "<html" in raw_text.lower():
                extracted = extract_main_html(raw_text)
                return apply_truncation(extracted)

            return apply_truncation(raw_text)
    except urllib.error.HTTPError as e:
        return f"HTTP Error {e.code}: {e.reason} while fetching {url}"
    except urllib.error.URLError as e:
        return f"Network Error: {e.reason} while fetching {url}"
    except Exception as e:
        return f"Error reading URL: {str(e)}"

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: fetch-url.py <URL>")
        sys.exit(1)
    target_url = sys.argv[1]
    print(fetch_url(target_url))
