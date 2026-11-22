# Aurora RT

Shader para **Minecraft Bedrock con RTX** (Windows). Se aplica **encima de un preset de BetterRTX** y le agrega:

- Cielo propio con **nubes volumétricas 3D** (se ven desde abajo y desde arriba, sombras de nubes).
- **Destello y lens flare del sol**, sol y luna propios.
- **Arcoíris** cuando llueve de día y **auroras boreales** de noche en biomas nevados (con el pack Aurora RT – Texturas).
- **Nubes reflejadas** en el agua y en los bloques lisos.
- **El End renovado**: agujero negro animado, galaxia que gira, nebulosa y planetas reales con sus lunas.
- Portal del End con estrellas.

La luz, las sombras, el agua y los charcos los hace el preset de BetterRTX que tengas. Aurora RT solo cambia el último paso de la imagen.

> **English below.**

## Instalación (fácil)

Descarga **Aurora_RT.zip** de la sección *Releases*, descomprímelo y haz doble clic en `Instalar_Aurora_RT.bat`.

- Necesitas Minecraft Bedrock para Windows con trazado de rayos y **Python 3** ([python.org](https://www.python.org/)).
- **Preset opcional:** si tienes instalado un preset de BetterRTX (desde [bedrock.graphics](https://bedrock.graphics)), Aurora RT se pone encima de él. Si no, se pone encima del RTX original. También puedes poner un `.rtpack` junto al instalador.
- No instala ningún pack de texturas: usa el que quieras.
- Si cambias de preset, o si Minecraft se actualiza o la app de Xbox lo "repara", vuelve a correr el instalador.

## Preset recomendado: Aurora RT – Luz

Aurora RT se ve mejor encima de nuestro preset de BetterRTX: [Aurora RT - Luz en bedrock.graphics](https://bedrock.graphics/community/aurora-rt-luz-298a6d) (en revisión por sus moderadores). También puedes armarlo tú con los ajustes: Solo compartimos **los ajustes** (no el código de BetterRTX); la página de BetterRTX arma el preset en tu PC:

1. Descarga [`preset/Aurora RT - Luz.json`](preset/Aurora%20RT%20-%20Luz.json).
2. Entra a [bedrock.graphics/creator](https://bedrock.graphics/creator), pulsa **Import from .rtpack** y elige ese archivo.
3. Ve a **Export → Build Preset → Install** (con Minecraft cerrado).
4. Corre el instalador de Aurora RT para ponerlo encima.

## Compilar tú mismo

Aurora RT no incluye archivos de BetterRTX ni de Microsoft: se compila **encima de tu propio preset**.

1. Instala [Python 3](https://www.python.org/).
2. Baja [DirectX Shader Compiler](https://github.com/microsoft/DirectXShaderCompiler/releases) y pon `dxc.exe`, `dxcompiler.dll` y `dxil.dll` en `herramientas\`.
3. Abre tu `.rtpack` (es un .zip) y copia su `RTXStub.material.bin` a `shader\tu_betterrtx\`.
4. Haz doble clic en `herramientas\Compilar_Aurora.bat` (tarda unos minutos).
5. El resultado queda en `salida\RTXStub.material.bin`. Instálalo igual que un preset de BetterRTX, reemplazando su `RTXStub.material.bin`.

## Ajustes

Todo se ajusta con `#define AR_...` en `shader/RTXStub/shaders/CopyToFinal.hlsl` y `Include/Renderer.hlsl` (altura y cobertura de las nubes, fuerza del destello, arcoíris, auroras, etc.).

## Créditos

Ver [CREDITOS.md](CREDITOS.md). Licencia MIT (ver [LICENSE](LICENSE)).

---

# Aurora RT (English)

A shader for **Minecraft Bedrock RTX** (Windows). It runs **on top of a BetterRTX preset** and adds:

- Custom sky with **3D volumetric clouds** (visible from below and above, with cloud shadows).
- **Sun glare and lens flare**, custom sun and moon.
- **Rainbows** in daytime rain and **northern lights** at night in snowy biomes (with the Aurora RT – Textures pack).
- **Clouds reflected** in water and smooth blocks.
- **A new End**: animated black hole, spinning galaxy, nebula and real planets with their moons.
- End portal filled with stars.

Lighting, shadows, water and puddles come from your BetterRTX preset. Aurora RT only replaces the final image pass.

## Install (easy)

Download **Aurora_RT.zip** from *Releases*, unzip it and double-click `Instalar_Aurora_RT.bat`. You need Minecraft Bedrock for Windows with ray tracing and **Python 3**. If you have a BetterRTX preset installed (from bedrock.graphics), Aurora RT goes on top of it; otherwise it goes on top of vanilla RTX. No texture pack is installed: use any pack you like. Run the installer again after changing presets or after a Minecraft update.

## Recommended preset: Aurora RT – Light

Aurora RT looks best on top of our BetterRTX preset: [Aurora RT - Luz on bedrock.graphics](https://bedrock.graphics/community/aurora-rt-luz-298a6d) (pending review). You can also build it yourself. We only share **the settings** (no BetterRTX code): download [`preset/Aurora RT - Luz.json`](preset/Aurora%20RT%20-%20Luz.json), open [bedrock.graphics/creator](https://bedrock.graphics/creator), click **Import from .rtpack**, pick the file, then **Export → Build Preset → Install**. Then run the Aurora RT installer.

## Build it yourself

Aurora RT ships no BetterRTX or Microsoft files. It is compiled **on top of your own preset**:

1. Install [Python 3](https://www.python.org/).
2. Get [DirectX Shader Compiler](https://github.com/microsoft/DirectXShaderCompiler/releases) and put `dxc.exe`, `dxcompiler.dll` and `dxil.dll` in `herramientas\`.
3. Open your `.rtpack` (it is a .zip) and copy its `RTXStub.material.bin` into `shader\tu_betterrtx\`.
4. Double-click `herramientas\Compilar_Aurora.bat` (takes a few minutes).
5. Output: `salida\RTXStub.material.bin`. Install it like a BetterRTX preset, replacing its `RTXStub.material.bin`.

## Credits

See [CREDITOS.md](CREDITOS.md). MIT License (see [LICENSE](LICENSE)).
