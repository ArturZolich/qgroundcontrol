/****************************************************************************
 *
 * (c) 2009-2020 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

import QtQuick
import QtGraphs
import QtQuick.Controls

import QGroundControl
import QGroundControl.Controls
import Custom 1.0

Item {
    id: _root

    // -------------------------------------------------------------------------
    // GLOBALS & STATE
    // -------------------------------------------------------------------------
    property Item pipView
    property Item pipState: chartPipState
    property bool isPip:    chartPipState.state === chartPipState.pipState

    property var dev213: ({"ip": "192.168.144.213", "metaFetched": false, "configData": null, "lastMeasurementRaw": "", "measurementMetaFlat": null, "csv": null, "hasNewData": false})
    property var dev136: ({"ip": "192.168.144.136", "metaFetched": false, "configData": null, "lastMeasurementRaw": "", "measurementMetaFlat": null, "csv": null, "hasNewData": false})

    QGCPalette { id: qgcPal }
    SpectralLogger { id: logger }

    Connections {
        target: QGroundControl.multiVehicleManager
        function onActiveVehicleChanged(vehicle) {
            logger.setVehicle(vehicle)
        }
    }

    Component.onCompleted: {
        var v = QGroundControl.multiVehicleManager.activeVehicle
        if (v) logger.setVehicle(v)
        logger.startSession()
        metaDiscoveryTimer.start()
    }

    Component.onDestruction: {
        logger.stopSession()
    }

    // -------------------------------------------------------------------------
    // TIMERS & DATA ACQUISITION (Original logic)
    // -------------------------------------------------------------------------

    Timer {
        id: metaDiscoveryTimer
        interval: 3000; repeat: true
        onTriggered: {
            var checkDone = function() {
                if (dev213.metaFetched && dev136.metaFetched) {
                    metaDiscoveryTimer.stop()
                    logger.saveMetaJSON(JSON.stringify({timestamp: new Date().toISOString(), device_213: dev213.configData, device_136: dev136.configData}))
                    measurementTimer.start()
                }
            }
            if (!dev213.metaFetched) checkDeviceMeta(dev213, checkDone)
            if (!dev136.metaFetched) checkDeviceMeta(dev136, checkDone)
        }
    }

    Timer {
        id: measurementTimer
        interval: 2500; repeat: true
        onTriggered: {
            checkDeviceMeasurement(dev213, processSynchronizedData)
            checkDeviceMeasurement(dev136, processSynchronizedData)
        }
    }

    function httpRequest(url, callback) {
        var xhr = new XMLHttpRequest()
        xhr.timeout = 3000
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) callback(xhr.responseText)
                else callback(null)
            }
        }
        xhr.ontimeout = function() { callback(null) }; xhr.onerror = function() { callback(null) }
        xhr.open("GET", url); xhr.send()
    }

    function checkDeviceMeta(deviceObj, doneCallback) {
        var base = "http://" + deviceObj.ip + "/dyn/load.jsn?file="
        var result = {}; var pending = 3; var failed = false
        function handleResponse(key, responseText) {
            if (!responseText) failed = true
            else { try { result[key] = JSON.parse(responseText) } catch (e) { failed = true } }
            pending--
            if (pending === 0) {
                if (!failed) { deviceObj.configData = result; deviceObj.metaFetched = true }
                doneCallback()
            }
        }
        httpRequest(base + "params.jsn", function(res) { handleResponse("params", res) })
        httpRequest(base + "config.jsn", function(res) { handleResponse("config", res) })
        httpRequest(base + "system.jsn", function(res) { handleResponse("system", res) })
    }

    function checkDeviceMeasurement(deviceObj, syncCallback) {
        var url = "http://" + deviceObj.ip + "/dyn/load.jsn?file=measurement.jsn"
        httpRequest(url, function(responseText) {
            if (!responseText) return
            if (responseText !== deviceObj.lastMeasurementRaw) {
                deviceObj.lastMeasurementRaw = responseText
                try { deviceObj.measurementMetaFlat = flattenMeasurement(JSON.parse(responseText)) } catch (e) { return }
                httpRequest("http://" + deviceObj.ip + "/dyn/spectrum.csv?type=measure", function(csvText) {
                    if (csvText) { deviceObj.csv = parseCSV(csvText); deviceObj.hasNewData = true; syncCallback() }
                })
            }
        })
    }

    function processSynchronizedData() {
        if (dev213.hasNewData && dev136.hasNewData) {
            dev213.hasNewData = false; dev136.hasNewData = false
            var result = computeSpectra(dev213.csv || [], dev136.csv || [])
            logger.logSpectrum(dev213.csv, dev136.csv, result.reflectance, dev213.measurementMetaFlat, dev136.measurementMetaFlat)
            updateChart(result)
        }
    }

    // -------------------------------------------------------------------------
    // MATH & PARSING
    // -------------------------------------------------------------------------

    function flattenMeasurement(json) {
        var result = {}
        for (var key in json) {
            var obj = json[key]
            for (var sub in obj) { result[key.replace(/\s+/g, "_") + "_" + sub] = obj[sub] }
        }
        return result
    }

    function parseCSV(text) {
        var lines = text.split("\n"); var result = []
        for (var i = 0; i < lines.length; i++) {
            if (!lines[i]) continue
            var parts = lines[i].split(";")
            result.push({ "x": Number(parts[0]), "y": Number(parts[1]) })
        }
        return result
    }

    function computeSpectra(data1, data2) {
        var rad = [], irr = [], ref = []
        var minY1 = Infinity, maxY1 = -Infinity, minY2 = Infinity, maxY2 = -Infinity, minY3 = Infinity, maxY3 = -Infinity
        for (var i = 0; i < Math.max(data1.length, data2.length); i++) {
            var x = data1[i] ? data1[i].x : (data2[i] ? data2[i].x : 0)
            var y1 = data1[i] ? data1[i].y : 0; var y2 = data2[i] ? data2[i].y : 0
            if (data1[i]) { rad.push({x:x, y:y1}); minY1 = Math.min(minY1, y1); maxY1 = Math.max(maxY1, y1) }
            if (data2[i]) { irr.push({x:x, y:y2}); minY2 = Math.min(minY2, y2); maxY2 = Math.max(maxY2, y2) }
            if (data1[i] && data2[i] && y2 !== 0) { 
                var rrs = y1 / y2; ref.push({x:x, y:rrs}); minY3 = Math.min(minY3, rrs); maxY3 = Math.max(maxY3, rrs) 
            }
        }
        var margin = function(mi, ma) { var r = ma - mi; return { min: mi - r*0.05, max: ma + r*0.05 } }
        return { radiance: rad, irradiance: irr, reflectance: ref, axisY1: margin(minY1, maxY1), axisY2: margin(minY2, maxY2), axisY3: margin(minY3, maxY3) }
    }

    function updateChart(result) {
        radianceSeries.clear(); irradianceSeries.clear(); reflectanceSeries.clear()
        for (var i = 0; i < result.radiance.length; i++) radianceSeries.append(result.radiance[i].x, result.radiance[i].y)
        for (var i = 0; i < result.irradiance.length; i++) irradianceSeries.append(result.irradiance[i].x, result.irradiance[i].y)
        for (var i = 0; i < result.reflectance.length; i++) reflectanceSeries.append(result.reflectance[i].x, result.reflectance[i].y)
        axisY1.min = result.axisY1.min; axisY1.max = result.axisY1.max
        axisY2.min = result.axisY2.min; axisY2.max = result.axisY2.max
        axisY3.min = result.axisY3.min; axisY3.max = result.axisY3.max
    }

    function applyOpacity(colorIn, opacity){ return Qt.rgba(colorIn.r, colorIn.g, colorIn.b, opacity) }

    // -------------------------------------------------------------------------
    // UI ELEMENTS (Corrected for QtGraphs 6.10.3)
    // -------------------------------------------------------------------------

    PipState { id: chartPipState; pipView: _root.pipView; isDark: true }

    GraphsView {
        id:                 chartView
        anchors.fill:       parent
        anchors.topMargin:  isPip ? 0 : (typeof toolbar !== 'undefined' ? toolbar.height : 0)
        
        marginTop:          isPip ? 0 : ScreenTools.defaultFontPixelHeight / 2
        marginRight:        isPip ? 0 : ScreenTools.defaultFontPixelWidth * 2
        marginBottom:       -ScreenTools.defaultFontPixelHeight / 2 
        marginLeft:         0

        theme: GraphsTheme {
            colorScheme:             qgcPal.globalTheme === QGCPalette.Light ? GraphsTheme.ColorScheme.Light : GraphsTheme.ColorScheme.Dark
            backgroundColor:         logger.triggerActive ? "#ffe6e6" : "transparent"
            backgroundVisible:       logger.triggerActive ? true : false
            plotAreaBackgroundColor: qgcPal.window
            grid.mainColor:          applyOpacity(qgcPal.text, 0.5)
            grid.subColor:           applyOpacity(qgcPal.text, 0.3)
            grid.mainWidth:          1
            labelBackgroundVisible:  false
            labelTextColor:          qgcPal.text
            axisXLabelFont.family:   ScreenTools.fixedFontFamily
            axisXLabelFont.pointSize: ScreenTools.smallFontPointSize
            axisYLabelFont.family:   ScreenTools.fixedFontFamily
            axisYLabelFont.pointSize: ScreenTools.smallFontPointSize
        }

        axisX: ValueAxis {
            id:             axisX
            min:            380
            max:            950
            titleText:      isPip ? "" : qsTr("Wavelength (nm)")
            lineVisible:    true
            visible:        !isPip
            labelDecimals:  0
        }

        LineSeries {
            id:             radianceSeries
            name:           "Radiance"
            axisX:          axisX
            axisY: ValueAxis { id: axisY1; titleText: isPip ? "" : "Lw"; visible: !isPip }
        }

        LineSeries {
            id:             irradianceSeries
            name:           "Irradiance"
            axisX:          axisX
            axisY: ValueAxis { id: axisY2; titleText: isPip ? "" : "Es"; visible: !isPip }
        }

        LineSeries {
            id:             reflectanceSeries
            name:           "Reflectance"
            axisX:          axisX
            axisY: ValueAxis { id: axisY3; titleText: isPip ? "" : "Rrs"; visible: !isPip }
        }
    }

    QGCLabel {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top:              parent.top
        anchors.topMargin:        ScreenTools.defaultFontPixelHeight * 0.5
        text:                     qsTr("Spectral Analysis")
        font.pointSize:           ScreenTools.mediumFontPointSize
        font.bold:                true
        visible:                  !isPip
        color:                    qgcPal.text
    }
}