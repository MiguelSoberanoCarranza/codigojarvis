#!/bin/bash

# Exit immediately if any command fails
set -e

echo "=== Iniciando compilación de JarvisNotch ==="

# 1. Limpiar construcciones anteriores
if [ -d "JarvisNotch.app" ]; then
    echo "Borrando JarvisNotch.app anterior..."
    rm -rf JarvisNotch.app
fi

# 2. Crear estructura del bundle .app
echo "Creando directorios del bundle..."
mkdir -p JarvisNotch.app/Contents/MacOS
mkdir -p JarvisNotch.app/Contents/Resources

# 3. Compilar archivos Swift
echo "Compilando archivos Swift con swiftc..."
# Usamos -O para optimizar la velocidad y compresión del binario.
# Incluimos los frameworks nativos necesarios: Cocoa, SwiftUI, IOKit
swiftc -O -o JarvisNotch.app/Contents/MacOS/JarvisNotch \
    main.swift \
    AppDelegate.swift \
    NotchWindow.swift \
    NotchStateManager.swift \
    ContentView.swift \
    MediaService.swift \
    WeatherService.swift \
    DashboardExtras.swift \
    -framework Cocoa \
    -framework SwiftUI \
    -framework IOKit \
    -framework EventKit \
    -sdk "$(xcrun --show-sdk-path)"

# 4. Copiar Info.plist al bundle
echo "Copiando Info.plist..."
cp Info.plist JarvisNotch.app/Contents/Info.plist

# 5. Asegurar permisos de ejecución en el binario principal
chmod +x JarvisNotch.app/Contents/MacOS/JarvisNotch

echo "=== Compilación exitosa! JarvisNotch.app ha sido creado ==="
echo "Para abrir la app: open JarvisNotch.app"
