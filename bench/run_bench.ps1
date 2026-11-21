# Reproducible memory & performance benchmark harness:
# Compares goose_ui (native Clang), goose_ui (headless), Qt 6.11.1 Widgets (C++ -O2),
# and Python Tkinter across identical 0 / 100 / 1,000 / 5,000-control workloads.
param(
    [int[]]$Counts = @(0, 100, 1000, 5000)
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $RepoRoot

try {
    Write-Host "=== Building goose_ui benchmark (native Clang -O2) ==="
    goose build bench/goose_ui_bench.goose
    $gooseExe = Join-Path $RepoRoot "bench\goose_ui_bench.exe"
    $gooseSizeKB = [math]::Round((Get-Item $gooseExe).Length / 1KB, 1)

    $qtExe = Join-Path $RepoRoot "bench\qt6_bench.exe"
    $qtRoot = "C:\Qt\6.11.1\mingw_64"
    $mingwBin = "C:\Qt\Tools\mingw1310_64\bin"
    $hasQt = (Test-Path "$qtRoot\include\QtWidgets") -and (Test-Path "$mingwBin\g++.exe")
    $qtSizeKB = 0
    $qtDllTotalKB = 0

    if ($hasQt) {
        Write-Host "=== Building Qt 6.11.1 Widgets benchmark (MinGW g++ -O2) ==="
        $env:PATH = "$qtRoot\bin;$mingwBin;$env:PATH"
        & "$mingwBin\g++.exe" -O2 -std=c++17 `
            "bench/qt6_bench.cpp" -o $qtExe `
            -I"$qtRoot\include" `
            -I"$qtRoot\include\QtCore" `
            -I"$qtRoot\include\QtGui" `
            -I"$qtRoot\include\QtWidgets" `
            -L"$qtRoot\lib" `
            -lQt6Widgets -lQt6Gui -lQt6Core -lpsapi
        if ($LASTEXITCODE -ne 0) { throw "Qt6 build failed" }
        $qtSizeKB = [math]::Round((Get-Item $qtExe).Length / 1KB, 1)
        $dlls = @("Qt6Core.dll", "Qt6Gui.dll", "Qt6Widgets.dll", "libstdc++-6.dll", "libgcc_s_seh-1.dll", "libwinpthread-1.dll")
        $dllSum = 0
        foreach ($d in $dlls) {
            $p = Join-Path "$qtRoot\bin" $d
            if (Test-Path $p) { $dllSum += (Get-Item $p).Length }
        }
        $qwin = Join-Path "$qtRoot\plugins\platforms" "qwindows.dll"
        if (Test-Path $qwin) { $dllSum += (Get-Item $qwin).Length }
        $qtDllTotalKB = [math]::Round($dllSum / 1KB, 1)

        $qtQuickExe = Join-Path $RepoRoot "bench\qt6_quick_bench.exe"
        Write-Host "=== Building Qt 6.11.1 Quick/QML GPU benchmark (MinGW g++ -O2) ==="
        & "$mingwBin\g++.exe" -O2 -std=c++17 `
            "bench/qt6_quick_bench.cpp" -o $qtQuickExe `
            -I"$qtRoot\include" `
            -I"$qtRoot\include\QtCore" `
            -I"$qtRoot\include\QtGui" `
            -I"$qtRoot\include\QtQml" `
            -I"$qtRoot\include\QtQuick" `
            -L"$qtRoot\lib" `
            -lQt6Quick -lQt6Qml -lQt6Gui -lQt6Core -lpsapi
        if ($LASTEXITCODE -ne 0) { throw "Qt6 Quick build failed" }
    }

    Write-Host "`nBinary / Deployment Footprint:"
    Write-Host ("  goose_ui standalone exe : {0} KB (0 external DLLs; only Windows system DLLs)" -f $gooseSizeKB)
    if ($hasQt) {
        Write-Host ("  Qt 6.11.1 exe + core DLLs: {0} KB exe + {1} KB required Qt/MinGW DLLs = {2} MB" -f $qtSizeKB, $qtDllTotalKB, [math]::Round(($qtSizeKB + $qtDllTotalKB)/1024.0, 1))
    }

    $results = @()

    foreach ($n in $Counts) {
        Write-Host "`n--- Running workload: $n controls ---"

        # goose_ui Software GDI (zero GPU driver overhead — apples-to-apples CPU vs Qt6 Widgets)
        $lineS = & $gooseExe --count $n --software
        Write-Host "  $lineS"
        $results += ($lineS | ConvertFrom-Json)

        # goose_ui Direct2D GPU (hardware-accelerated — apples-to-apples GPU vs Qt6 Quick)
        $line = & $gooseExe --count $n
        Write-Host "  $line"
        $results += ($line | ConvertFrom-Json)

        # goose_ui headless (pure Goose data-stack footprint)
        $lineH = & $gooseExe --count $n --headless
        Write-Host "  $lineH"
        $results += ($lineH | ConvertFrom-Json)

        # Qt 6.11.1 Widgets (real Win32 + Qt6 CPU raster window)
        if ($hasQt) {
            $lineQ = & $qtExe --count $n
            Write-Host "  $lineQ"
            $results += ($lineQ | ConvertFrom-Json)

            # Qt 6.11.1 Quick/QML (real GPU D3D11 window; cap at 1000 controls because QML Repeater is heavy)
            if ($n -le 1000) {
                $lineQQ = & $qtQuickExe --count $n
                Write-Host "  $lineQQ"
                $results += ($lineQQ | ConvertFrom-Json)
            }
        }

        # Python Tkinter (real Tk window; skip 5000 if too slow, or run all)
        if ($n -le 1000) {
            $lineT = & python "bench/tk_bench.py" --count $n
            Write-Host "  $lineT"
            $results += ($lineT | ConvertFrom-Json)
        }
    }

    $summary = [PSCustomObject]@{
        goose_exe_kb = $gooseSizeKB
        qt6_exe_kb = $qtSizeKB
        qt6_dlls_kb = $qtDllTotalKB
        runs = $results
    }
    $outPath = Join-Path $RepoRoot "bench\results.json"
    $summary | ConvertTo-Json -Depth 5 | Set-Content -Path $outPath -Encoding UTF8

    Write-Host "`n=== Summary Table (Private Bytes / Working Set / Total Time) ==="
    $results | ForEach-Object {
        [PSCustomObject]@{
            Framework    = $_.framework
            Controls     = $_.controls
            Private_MB   = [math]::Round($_.private_bytes / 1MB, 2)
            WorkingSet_MB= [math]::Round($_.working_set / 1MB, 2)
            PeakWS_MB    = [math]::Round($_.peak_working_set / 1MB, 2)
            Total_ms     = $_.total_ms
        }
    } | Format-Table -AutoSize
}
finally {
    Pop-Location
}
