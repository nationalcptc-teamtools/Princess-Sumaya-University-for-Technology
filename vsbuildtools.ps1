# Visual studio 2019 build tools + cpp build tools 
choco install visualstudio2019buildtools visualstudio2019-workload-vctools -y

# add msbuild to path
[System.Environment]::SetEnvironmentVariable("Path", [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine) + ";C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin", [System.EnvironmentVariableTarget]::Machine)

# refresh env
refreshenv