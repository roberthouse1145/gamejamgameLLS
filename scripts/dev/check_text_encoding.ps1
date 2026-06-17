param(
    [switch]$Staged
)

$ErrorActionPreference = "Stop"

$repo_root = Resolve-Path (Join-Path $PSScriptRoot "..\\..")
Set-Location $repo_root

$text_extensions = @(
    ".gd",
    ".tscn",
    ".tres",
    ".godot",
    ".cfg",
    ".json",
    ".md",
    ".txt",
    ".import",
    ".uid"
)

$exact_text_names = @(
    ".editorconfig",
    ".gitattributes"
)

$ignored_prefixes = @(
    ".git\",
    ".godot\",
    ".kiro\",
    "__pycache__\"
)

$utf8_decoder = [System.Text.UTF8Encoding]::new($false, $true)
$errors = [System.Collections.Generic.List[string]]::new()
$repo_root_path = [System.IO.Path]::GetFullPath($repo_root)
if (-not $repo_root_path.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
    $repo_root_path += [System.IO.Path]::DirectorySeparatorChar
}

function Is-TextTarget {
    param(
        [string]$RelativePath
    )

    $file_name = [System.IO.Path]::GetFileName($RelativePath)
    if ($exact_text_names -contains $file_name) {
        return $true
    }

    $extension = [System.IO.Path]::GetExtension($RelativePath).ToLowerInvariant()
    return $text_extensions -contains $extension
}

function Is-IgnoredPath {
    param(
        [string]$RelativePath
    )

    foreach ($prefix in $ignored_prefixes) {
        if ($RelativePath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Get-TargetPaths {
    if ($Staged) {
        $staged_paths = git diff --cached --name-only --diff-filter=ACMR
        return $staged_paths | Where-Object { $_ -and -not (Is-IgnoredPath $_) -and (Is-TextTarget $_) }
    }

    $all_files = Get-ChildItem -Recurse -File
    return $all_files |
        ForEach-Object {
            $full_name = [System.IO.Path]::GetFullPath($_.FullName)
            if ($full_name.StartsWith($repo_root_path, [System.StringComparison]::OrdinalIgnoreCase)) {
                $full_name.Substring($repo_root_path.Length)
            } else {
                $_.Name
            }
        } |
        Where-Object { -not (Is-IgnoredPath $_) } |
        Where-Object { Is-TextTarget $_ }
}

function Test-FileEncoding {
    param(
        [string]$RelativePath
    )

    $absolute_path = Join-Path $repo_root $RelativePath
    if (-not (Test-Path -LiteralPath $absolute_path)) {
        return
    }

    $bytes = [System.IO.File]::ReadAllBytes($absolute_path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $errors.Add("${RelativePath} : contains UTF-8 BOM")
        return
    }

    try {
        $content = $utf8_decoder.GetString($bytes)
    } catch {
        $errors.Add("${RelativePath} : is not valid UTF-8")
        return
    }

    if ($content.Contains("`r`n")) {
        $errors.Add("${RelativePath} : contains CRLF line endings")
    }
}

$target_paths = Get-TargetPaths | Sort-Object -Unique
foreach ($relative_path in $target_paths) {
    Test-FileEncoding -RelativePath $relative_path
}

if ($errors.Count -gt 0) {
    Write-Host "Encoding check failed. Please save these files as UTF-8 without BOM and with LF line endings:" -ForegroundColor Red
    foreach ($message in $errors) {
        Write-Host "  - $message" -ForegroundColor Red
    }
    exit 1
}

Write-Host "Encoding check passed for $($target_paths.Count) file(s)." -ForegroundColor Green
