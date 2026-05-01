/****************************************************************************
 *
 * (c) 2009-2020 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/
import QtQuick 2.12
import QtCharts 2.3
import QtQuick.Controls 2.12

import QGroundControl 1.0
import QGroundControl.Controls 1.0
import Custom 1.0

Item {
    id: _root

    // -------------------------------------------------------------------------
    // GLOBALS & STATE
    // -------------------------------------------------------------------------
    property Item pipView
    property Item pipState: chartPipState
    property bool isPip: chartPipState.state === chartPipState.pipState

    property var dev213: ({
        ip: "192.168.144.213",
        metaFetched: false,
        configData: null,
        lastMeasurementRaw: "",
        measurementMetaFlat: null,
        csv: null,
        hasNewData: false
    })

    property var dev136: ({
        ip: "192.168.144.136",
        metaFetched: false,
        configData: null,
        lastMeasurementRaw: "",
        measurementMetaFlat: null,
        csv: null,
        hasNewData: false
    })

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

        // Start looking for the sensors
        metaDiscoveryTimer.start()
    }

    Component.onDestruction: {
        logger.stopSession()
    }

    // -------------------------------------------------------------------------
    // TIMERS (The core loop logic)
    // -------------------------------------------------------------------------

    // Phase 1: Waits for both sensors to appear and downloads their config JSONs
    Timer {
        id: metaDiscoveryTimer
        interval: 3000 // Poll every 2 seconds until successful
        repeat: true
        running: false
        onTriggered: {
            var checkDone = function() {
                if (dev213.metaFetched && dev136.metaFetched) {
                    metaDiscoveryTimer.stop()

                    var combinedMeta = {
                        timestamp: new Date().toISOString(),
                        device_213: dev213.configData,
                        device_136: dev136.configData
                    }

                    logger.saveMetaJSON(JSON.stringify(combinedMeta))
                    console.warn("All Meta Saved. Starting Measurement Loop.")
                    measurementTimer.start()
                }
            }

            if (!dev213.metaFetched) checkDeviceMeta(dev213, checkDone)
            if (!dev136.metaFetched) checkDeviceMeta(dev136, checkDone)
        }
    }

    // Phase 2: Polls for measurements and triggers processing when synchronized
    Timer {
        id: measurementTimer
        interval: 2500 // Poll every 1 second
        repeat: true
        running: false
        onTriggered: {
            checkDeviceMeasurement(dev213, processSynchronizedData)
            checkDeviceMeasurement(dev136, processSynchronizedData)
        }
    }

    // -------------------------------------------------------------------------
    // DATA ACQUISITION LOGIC
    // -------------------------------------------------------------------------

    // Generic HTTP Request Helper (Replaces messy manual timeouts)
    function httpRequest(url, callback) {
        var xhr = new XMLHttpRequest()
        xhr.timeout = 3000 // 3 seconds timeout

        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    callback(xhr.responseText)
                } else {
                    callback(null)
                }
            }
        }
        xhr.ontimeout = function() { callback(null) }
        xhr.onerror = function() { callback(null) }

        xhr.open("GET", url)
        xhr.send()
    }

    // Phase 1 Logic: Fetch params, config, system
    function checkDeviceMeta(deviceObj, doneCallback) {
        var base = "http://" + deviceObj.ip + "/dyn/load.jsn?file="
        var result = {}
        var pending = 3
        var failed = false

        function handleResponse(key, responseText) {
            if (!responseText) {
                failed = true
            } else {
                try { result[key] = JSON.parse(responseText) }
                catch (e) { failed = true }
            }

            pending--
            if (pending === 0) {
                if (!failed) {
                    console.warn("Meta successfully fetched for", deviceObj.ip)
                    deviceObj.configData = result
                    deviceObj.metaFetched = true
                }
                doneCallback()
            }
        }

        httpRequest(base + "params.jsn", function(res) { handleResponse("params", res) })
        httpRequest(base + "config.jsn", function(res) { handleResponse("config", res) })
        httpRequest(base + "system.jsn", function(res) { handleResponse("system", res) })
    }

    // Phase 2 Logic: Fetch measurement, check for changes, fetch CSV
    function checkDeviceMeasurement(deviceObj, syncCallback) {
        var url = "http://" + deviceObj.ip + "/dyn/load.jsn?file=measurement.jsn"

        httpRequest(url, function(responseText) {
            if (!responseText) return // Sensor unavailable or timeout

            if (responseText !== deviceObj.lastMeasurementRaw) {
                deviceObj.lastMeasurementRaw = responseText

                try {
                    var json = JSON.parse(responseText)
                    deviceObj.measurementMetaFlat = flattenMeasurement(json)
                } catch (e) { return }

                // Data changed, fetch the CSV
                var csvUrl = "http://" + deviceObj.ip + "/dyn/spectrum.csv?type=measure"
                httpRequest(csvUrl, function(csvText) {
                    if (csvText) {
                        deviceObj.csv = parseCSV(csvText)
                        deviceObj.hasNewData = true
                        syncCallback() // Attempt sync
                    }
                })
            }
        })
    }

    // Phase 2 Logic: Synchronize and execute logging/charting
    function processSynchronizedData() {
        if (dev213.hasNewData && dev136.hasNewData) {
            // Consume the triggers
            dev213.hasNewData = false
            dev136.hasNewData = false

            var d1 = dev213.csv || []
            var d2 = dev136.csv || []

            var result = computeSpectra(d1, d2)

            logger.logSpectrum(
                d1,
                d2,
                result.reflectance,
                dev213.measurementMetaFlat,
                dev136.measurementMetaFlat
            )

            updateChart(result)
        }
    }

    // -------------------------------------------------------------------------
    // DATA PARSING & MATH (Untouched logic)
    // -------------------------------------------------------------------------

    function flattenMeasurement(json) {
        var result = {}
        for (var key in json) {
            var obj = json[key]
            for (var sub in obj) {
                var flatKey = key.replace(/\s+/g, "_") + "_" + sub
                result[flatKey] = obj[sub]
            }
        }
        return result
    }

    function parseCSV(text) {
        var lines = text.split("\n")
        var result = []
        for (var i = 0; i < lines.length; i++) {
            if (!lines[i]) continue
            var parts = lines[i].split(";")
            result.push({ "x": Number(parts[0]), "y": Number(parts[1]) })
        }
        return result
    }

    function computeSpectra(data1, data2) {
        var radiance = []
        var irradiance = []
        var reflectance = []

        var minY1 = Number.POSITIVE_INFINITY, maxY1 = Number.NEGATIVE_INFINITY
        var minY2 = Number.POSITIVE_INFINITY, maxY2 = Number.NEGATIVE_INFINITY
        var minY3 = Number.POSITIVE_INFINITY, maxY3 = Number.NEGATIVE_INFINITY

        var has1 = data1.length > 0
        var has2 = data2.length > 0

        for (var i = 0; i < Math.max(data1.length, data2.length); i++) {
            var x = (has1 && data1[i]) ? data1[i].x : (has2 && data2[i]) ? data2[i].x : 0
            var y1 = has1 && data1[i] ? data1[i].y : 0
            var y2 = has2 && data2[i] ? data2[i].y : 0

            if (has1) {
                radiance.push({ x: x, y: y1 })
                if (y1 < minY1) minY1 = y1
                if (y1 > maxY1) maxY1 = y1
            }
            if (has2) {
                irradiance.push({ x: x, y: y2 })
                if (y2 < minY2) minY2 = y2
                if (y2 > maxY2) maxY2 = y2
            }
            if (has1 && has2 && y2 !== 0) {
                var rrs = y1 / y2
                reflectance.push({ x: x, y: rrs })
                if (rrs < minY3) minY3 = rrs
                if (rrs > maxY3) maxY3 = rrs
            }
        }

        function addMargin(minVal, maxVal) {
            var range = maxVal - minVal
            return {
                min: minVal - range * 0.05,
                max: maxVal + range * 0.05
            }
        }

        return {
            radiance: radiance,
            irradiance: irradiance,
            reflectance: reflectance,
            axisY1: addMargin(minY1, maxY1),
            axisY2: addMargin(minY2, maxY2),
            axisY3: addMargin(minY3, maxY3)
        }
    }

    // -------------------------------------------------------------------------
    // UI ELEMENTS & UPDATES
    // -------------------------------------------------------------------------

    PipState {
        id: chartPipState
        pipView: _root.pipView
        isDark: true
        onStateChanged: _root.updateScreen()
    }

    function updateScreen() {
        if (chartPipState.state === chartPipState.fullState) {
            chartView.title = "Calibrated Data"
            chartView.legend.visible = true
            axisX.visible = true
            axisY1.visible = true
            axisY2.visible = true
            axisY3.visible = true
            chartView.margins.left = 30
            chartView.margins.right = 30
            chartView.margins.top = 10
            chartView.margins.bottom = 50
        }

        if (chartPipState.state === chartPipState.pipState) {
            chartView.title = ""
            chartView.legend.visible = false
            axisX.visible = false
            axisY1.visible = false
            axisY2.visible = false
            axisY3.visible = false
            chartView.margins.left = 0
            chartView.margins.right = 0
            chartView.margins.top = 0
            chartView.margins.bottom = 0
        }
    }

    function updateChart(result) {
        radianceSeries.clear()
        irradianceSeries.clear()
        reflectanceSeries.clear()

        for (var i = 0; i < result.radiance.length; i++) radianceSeries.append(result.radiance[i].x, result.radiance[i].y)
        for (var i = 0; i < result.irradiance.length; i++) irradianceSeries.append(result.irradiance[i].x, result.irradiance[i].y)
        for (var i = 0; i < result.reflectance.length; i++) reflectanceSeries.append(result.reflectance[i].x, result.reflectance[i].y)

        axisY1.min = result.axisY1.min
        axisY1.max = result.axisY1.max

        axisY2.min = result.axisY2.min
        axisY2.max = result.axisY2.max

        axisY3.min = result.axisY3.min
        axisY3.max = result.axisY3.max
    }

    ChartView {
        id: chartView
        anchors.fill: parent
        anchors.topMargin: isPip ? 0 : toolbar.height
        antialiasing: true
        title: "Calibrated Data"
        backgroundColor: "white"
        titleFont: Qt.font({ "family": "Helvetica", "pointSize": 18, "bold": true })

        ValueAxis {
            id: axisX
            min: 380
            max: 950
            titleText: "Wavelength"
            labelsFont: Qt.font({ "family": "Helvetica", "pointSize": 12, "bold": true })
        }

        ValueAxis { id: axisY1; titleText: "Radiance - Lw"; labelsFont: Qt.font({ "family": "Helvetica", "pointSize": 12, "bold": true }) }
        ValueAxis { id: axisY2; titleText: "Irradiance - Es"; labelsFont: Qt.font({ "family": "Helvetica", "pointSize": 12, "bold": true }) }
        ValueAxis { id: axisY3; titleText: "Reflectance - Rrs"; labelsFont: Qt.font({ "family": "Helvetica", "pointSize": 12, "bold": true }) }

        LineSeries { id: radianceSeries; name: "Radiance"; axisX: axisX; axisY: axisY1 }
        LineSeries { id: irradianceSeries; name: "Irradiance"; axisX: axisX; axisY: axisY2 }
        LineSeries { id: reflectanceSeries; name: "Reflectance"; axisX: axisX; axisYRight: axisY3 }
    }
}
