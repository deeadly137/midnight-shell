qml_module(caelestia-components
    URI Caelestia.Components
    SOURCES
        lazylistview.cpp
        wavyline.cpp
        buttonrow.cpp
        circularindicatormanager.cpp
        linearindicatormanager.cpp
        sparklineitem.cpp
        visualiserbars.cpp
    LIBRARIES
        Qt::Gui
        Qt::Quick
        caelestia-core
    DEPENDENCIES
        Caelestia
)

qt_add_shaders(caelestia-components "component_shaders"
    BATCHABLE OPTIMIZED NOHLSL NOMSL
    GLSL "300es,330"
    PREFIX "/"
    FILES
        shaders/visualiser.frag
)

