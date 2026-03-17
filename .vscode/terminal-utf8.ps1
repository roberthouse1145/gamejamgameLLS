$utf8_no_bom = New-Object System.Text.UTF8Encoding($false)

[Console]::InputEncoding = $utf8_no_bom
[Console]::OutputEncoding = $utf8_no_bom
$OutputEncoding = $utf8_no_bom

$null = & chcp 65001

$PSDefaultParameterValues["Out-File:Encoding"] = "utf8"
$PSDefaultParameterValues["Set-Content:Encoding"] = "utf8"
$PSDefaultParameterValues["Add-Content:Encoding"] = "utf8"

try {
    [System.Console]::Title = "PowerShell UTF-8"
} catch {
}
