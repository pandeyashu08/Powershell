#pwsh theme

oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\paradox.omp.json" | Invoke-Expression


function admin{
start-process wt -verb runas;exit
}

function nano($file){
& "C:\Program Files\Git\usr\bin\nano.exe" $file
}

function vi($file){
& "C:\Program Files\Git\usr\bin\vim.exe" $file
}
sal -name vim -Value vi

function whereis($file){
gcm $file -all | select CommandType,Name,Source
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

#Setting PSReadline MenuComplete
Set-PSReadLineKeyHandler -Chord Alt+a -Function "MenuComplete"

$Desk = "C:\Users\Ashutosh\Desktop\"
$StartMenu = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs'

sal -Name neofetch -Value winfetch

<# New-PSDrive -Name "Desk" -PSProvider FileSystem -Root "C:\Users\Ashutosh\Desktop\" -Scope Global 
<choco-cleaner> To clean temp files
#>
