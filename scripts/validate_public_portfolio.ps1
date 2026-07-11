$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$contentRoots = @(
    (Join-Path $repoRoot "README.md"),
    (Join-Path $repoRoot "cases"),
    (Join-Path $repoRoot "demos")
)

$publicFiles = foreach ($root in $contentRoots) {
    if (Test-Path -LiteralPath $root -PathType Leaf) {
        Get-Item -LiteralPath $root
    }
    elseif (Test-Path -LiteralPath $root -PathType Container) {
        Get-ChildItem -LiteralPath $root -Recurse -File
    }
}

$errors = [System.Collections.Generic.List[string]]::new()
$sensitivePatterns = [ordered]@{
    "former-employer" = '\u65B9\u5BB6\u94FA\u5B50'
    "personal-name"   = '\u65B9\u654F|\u90B1\u5C11\u5F6C'
    "phone"           = '(?<!\d)1[3-9]\d{9}(?!\d)'
    "personal-email"  = 'qiu_shaobin@163\.com'
    "windows-path"    = '(?:[A-Za-z]:\\|C:/Users/)'
    "api-secret"      = '(?i)(?:sk-[A-Za-z0-9_-]{12,}|(?:api[_-]?key|secret|token|cookie)\s*[:=]\s*[''"]?[A-Za-z0-9_./+-]{8,})'
}

foreach ($file in $publicFiles) {
    $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    foreach ($entry in $sensitivePatterns.GetEnumerator()) {
        if ($text -match $entry.Value) {
            $relative = [IO.Path]::GetRelativePath($repoRoot, $file.FullName)
            $errors.Add("Sensitive pattern '$($entry.Key)' found in $relative")
        }
    }
}

$markdownFiles = $publicFiles | Where-Object Extension -eq ".md"
$linkPattern = '!?(?:\[[^\]]*\])\((?<target>[^)]+)\)'

foreach ($file in $markdownFiles) {
    $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    foreach ($match in [regex]::Matches($text, $linkPattern)) {
        $target = $match.Groups["target"].Value.Trim()
        $target = ($target -split '\s+"', 2)[0]
        if ($target -match '^(?:https?://|mailto:|#)') { continue }

        $pathPart = [uri]::UnescapeDataString(($target -split '#', 2)[0])
        if ([string]::IsNullOrWhiteSpace($pathPart)) { continue }

        $resolved = Join-Path $file.DirectoryName $pathPart
        if (-not (Test-Path -LiteralPath $resolved)) {
            $relative = [IO.Path]::GetRelativePath($repoRoot, $file.FullName)
            $errors.Add("Broken local link in ${relative}: $target")
        }
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}

Write-Host "PASS: public portfolio validation completed"
