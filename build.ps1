# kOS Build Script

Write-Host "`n=== kOS Build System ===" -ForegroundColor Cyan
Write-Host "Building all kernels...`n" -ForegroundColor Yellow

# Assemble bootloader
Write-Host "[1/4] Assembling JBoot bootloader..." -ForegroundColor Green
& 'C:\Program Files\NASM\nasm.exe' -f bin jboot.asm -o jboot.bin
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ jboot.bin created" -ForegroundColor Green
} else {
    Write-Host "  ✗ Failed!" -ForegroundColor Red
    exit 1
}

# Assemble K122E
Write-Host "[2/4] Assembling K122E kernel..." -ForegroundColor Green
& 'C:\Program Files\NASM\nasm.exe' -f bin k122e.asm -o k122e.bin
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ k122e.bin created" -ForegroundColor Green
} else {
    Write-Host "  ✗ Failed!" -ForegroundColor Red
    exit 1
}

# Assemble K122P
Write-Host "[3/4] Assembling K122P kernel..." -ForegroundColor Green
& 'C:\Program Files\NASM\nasm.exe' -f bin k122p.asm -o k122p.bin
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ k122p.bin created" -ForegroundColor Green
} else {
    Write-Host "  ✗ Failed!" -ForegroundColor Red
    exit 1
}

# Assemble K122A
Write-Host "[4/4] Assembling K122A kernel..." -ForegroundColor Green
& 'C:\Program Files\NASM\nasm.exe' -f bin k122a.asm -o k122a.bin
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ k122a.bin created" -ForegroundColor Green
} else {
    Write-Host "  ✗ Failed!" -ForegroundColor Red
    exit 1
}

# Create disk image
Write-Host "`nCreating bootable disk image..." -ForegroundColor Yellow
cmd /c "copy /b jboot.bin + k122e.bin + k122p.bin + k122a.bin os.img" | Out-Null
if (Test-Path os.img) {
    $size = (Get-Item os.img).Length
    Write-Host "  ✓ os.img created ($size bytes)" -ForegroundColor Green
} else {
    Write-Host "  ✗ Failed to create disk image!" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== Build Complete! ===" -ForegroundColor Cyan
Write-Host "`nTo run: qemu-system-i386 -drive file=os.img,format=raw,index=0,media=disk" -ForegroundColor Yellow
