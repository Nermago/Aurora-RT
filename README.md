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

Lo más sencillo es usar el **instalador de un clic "Instalar Aurora RT"** (se publicará en la sección *Releases*).

Necesitas:
1. Minecraft Bedrock para Windows con trazado de rayos.
2. Un preset de BetterRTX (recomendado: **Aurora RT – Luz**, en [bedrock.graphics](https://bedrock.graphics)).
3. Opcional: el pack de texturas **Aurora RT – Texturas** (CurseForge).

Nota: cuando Minecraft se actualiza o la app de Xbox lo "repara", el juego vuelve a su RTX original. Solo vuelve a correr el instalador.

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

Use the **one-click installer "Install Aurora RT"** from *Releases* (coming soon). You need Minecraft Bedrock for Windows with ray tracing, a BetterRTX preset (recommended: **Aurora RT – Light** on [bedrock.graphics](https://bedrock.graphics)) and, optionally, the **Aurora RT – Textures** pack (CurseForge).

If Minecraft updates or the Xbox app "repairs" it, the game goes back to vanilla RTX. Just run the installer again.

## Build it yourself

Aurora RT ships no BetterRTX or Microsoft files. It is compiled **on top of your own preset**:

1. Install [Python 3](https://www.python.org/).
2. Get [DirectX Shader Compiler](https://github.com/microsoft/DirectXShaderCompiler/releases) and put `dxc.exe`, `dxcompiler.dll` and `dxil.dll` in `herramientas\`.
3. Open your `.rtpack` (it is a .zip) and copy its `RTXStub.material.bin` into `shader\tu_betterrtx\`.
4. Double-click `herramientas\Compilar_Aurora.bat` (takes a few minutes).
5. Output: `salida\RTXStub.material.bin`. Install it like a BetterRTX preset, replacing its `RTXStub.material.bin`.

## Credits

See [CREDITOS.md](CREDITOS.md). MIT License (see [LICENSE](LICENSE)).
