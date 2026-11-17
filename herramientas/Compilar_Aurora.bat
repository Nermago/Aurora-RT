@echo off
chcp 65001 >nul
cd /d "%~dp0.."
echo === Aurora RT: compilar encima de tu BetterRTX ===
if not exist "shader\tu_betterrtx\RTXStub.material.bin" (
  echo Falta shader\tu_betterrtx\RTXStub.material.bin  ^(lee PON_AQUI_TU_BETTERRTX.txt^)
  pause & exit /b 1
)
if not exist "herramientas\dxc.exe" (
  echo Falta dxc.exe: bajalo de https://github.com/microsoft/DirectXShaderCompiler/releases
  echo y pon dxc.exe, dxcompiler.dll y dxil.dll en la carpeta herramientas.
  pause & exit /b 1
)
python -m pip install --user --upgrade lazurite==0.12.0 > compilar_log.txt 2>&1
if not exist salida mkdir salida
python -m lazurite build shader -o salida --max-workers 2 --dxc "%~dp0dxc.exe" >> compilar_log.txt 2>&1
if exist "salida\RTXStub.material.bin" (
  echo Listo: salida\RTXStub.material.bin
) else (
  echo Algo fallo. Revisa compilar_log.txt
)
pause
