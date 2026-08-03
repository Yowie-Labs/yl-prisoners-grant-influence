$repoRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$project = Join-Path $repoRoot 'src\YL.Prisoners.LordsGrantInfluence.csproj'

& dotnet build $project -c Release -p:Platform=x64
exit $LASTEXITCODE
