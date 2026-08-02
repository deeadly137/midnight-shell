qml_module(caelestia-components
    URI Caelestia.Components
    SOURCES
        lazylistview.cpp
        wavyline.cpp
        buttonrow.cpp
        xembeditem.cpp
        xembeditem.hpp
    LIBRARIES
        Qt::Quick
        caelestia-services
        PkgConfig::XCB
)
