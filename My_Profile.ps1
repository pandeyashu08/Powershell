function admin {
start-process wt -verb runas;exit
}

function nano($file) {
& "C:\Program Files\Git\usr\bin\nano.exe" $file
}

function vi($file) {
& "C:\Program Files\Git\usr\bin\vim.exe" $file
}

function vim {
    vi
}

# Import the Chocolatey Profile that contains the necessary code to enable
# tab-completions to function for `choco`.
# Be aware that if you are missing these lines from your profile, tab completion
# for `choco` will not function.
# See https://ch0.co/tab-completion for details.
$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if (Test-Path($ChocolateyProfile)) {
Import-Module "$ChocolateyProfile"
}

<#<function python{
& "C:\Python311\python.exe" 
}#>

# Git commands

function git-status {
    git status
}

function git-branch {
    git branch
}

function git-clone($repository) {
    git clone $repository
}

# System information
function system-info {
    Get-ComputerInfo
}

function list-drives {
    Get-WmiObject -Class Win32_LogicalDisk
}
 
# Utility Functions
function show-hidden-files {
    Get-ChildItem -Force
}

function clear-screen {
    Clear-Host
}
