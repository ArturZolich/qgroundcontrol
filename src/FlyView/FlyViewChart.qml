
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

	SpectralLogger {
		id: logger
	}

	Connections {
		target: QGroundControl.multiVehicleManager

		function onActiveVehicleChanged(vehicle) {
			logger.setVehicle(vehicle)
		}
	}
		
	
	Component.onCompleted: {
        var v = QGroundControl.multiVehicleManager.activeVehicle
        if (v)
            logger.setVehicle(v)

        logger.startSession()

        fetchAllMeta(function(meta) {
		    meta.timestamp = new Date().toISOString()
            logger.saveMetaJSON(JSON.stringify(meta))
        })
    }

	
	Component.onDestruction: {
		logger.stopSession()
	}
	
    property Item pipView
    property Item pipState: chartPipState
    property bool isPip: chartPipState.state === chartPipState.pipState



    PipState {
        id: chartPipState
        pipView: _root.pipView
        isDark: true

        onStateChanged: {
            _root.updateScreen()
        }
    }

      
        

    property var radianceData: []
    property var irradianceData: []
    property var reflectanceData: []
    property string userComment: ""



    ChartView {
        id: chartView
        anchors.fill: parent
        anchors.topMargin: isPip ? 0 : toolbar.height
        antialiasing: true
        title: "Calibrated Data"
		backgroundColor: "white"						
        titleFont: Qt.font({
                               "family": "Helvetica",
                               "pointSize": 18,
                               "bold": true
                           })

        ValueAxis {
            id: axisX
            min: 380
            max: 950
            titleText: "Wavelength"
            labelsFont: Qt.font({
                                    "family": "Helvetica",
                                    "pointSize": 12,
                                    "bold": true
                                })
        }

        ValueAxis {
            id: axisY1
            titleText: "Radiance - Lw"
            labelsFont: Qt.font({
                                    "family": "Helvetica",
                                    "pointSize": 12,
                                    "bold": true
                                })
        }

        ValueAxis {
            id: axisY2
            titleText: "Irradiance - Es"
            labelsFont: Qt.font({
                                    "family": "Helvetica",
                                    "pointSize": 12,
                                    "bold": true
                                })
        }

        ValueAxis {
            id: axisY3
            titleText: "Reflectance - Rrs"
            labelsFont: Qt.font({
                                    "family": "Helvetica",
                                    "pointSize": 12,
                                    "bold": true
                                })
        }

        LineSeries {
            id: radianceSeries
            name: "Radiance"
            axisX: axisX
            axisY: axisY1
        }

        LineSeries {
            id: irradianceSeries
            name: "Irradiance"
            axisX: axisX
            axisY: axisY2
        }

        LineSeries {
            id: reflectanceSeries
            name: "Reflectance"
            axisX: axisX
            axisYRight: axisY3
        }
    }

    Timer {
        interval: 2500
        running: true
        repeat: true
        onTriggered: loadData()
    }

    function updateScreen() {

        if (chartPipState.state === chartPipState.fullState) {
            console.log("Now in Fullscreen mode")

            // Restore title
            chartView.title = "Calibrated Data"

            // Show legend
            chartView.legend.visible = true

            // Show axes
            axisX.visible = true
            axisY1.visible = true
            axisY2.visible = true
            axisY3.visible = true

            // Optional: restore margins
            chartView.margins.left = 30
            chartView.margins.right = 30
            chartView.margins.top = 10
            chartView.margins.bottom = 50
        }

        if (chartPipState.state === chartPipState.pipState) {
            console.log("Now in PIP mode")

            // Remove title
            chartView.title = ""

            // Hide legend
            chartView.legend.visible = false

            // Hide all axes
            axisX.visible = false
            axisY1.visible = false
            axisY2.visible = false
            axisY3.visible = false

            // Remove margins so lines fill entire area
            chartView.margins.left = 0
            chartView.margins.right = 0
            chartView.margins.top = 0
            chartView.margins.bottom = 0
        }
    }

function fetchJSONWithRetry(url, retries, delayMs, callback) {
    var attempt = 0

    function tryFetch() {
        var xhr = new XMLHttpRequest()

        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE) {

                if (xhr.status === 200) {
                    try {
                        var obj = JSON.parse(xhr.responseText)
                        callback(obj)
                        return
                    } catch (e) {
                        console.log("JSON parse error:", url)
                    }
                }

                attempt++
                if (attempt < retries) {
                    console.log("Retry", attempt, url)
                    Qt.createQmlObject(
                        'import QtQuick 2.0; Timer { interval: ' + delayMs + '; running: true; repeat: false; onTriggered: tryFetch(); }',
                        _root
                    )
                } else {
                    console.log("Failed after retries:", url)
                    callback(null)
                }
            }
        }

        xhr.open("GET", url)
        xhr.send()
    }

    tryFetch()
}


////////////////////////////////////////////////

function fetchDeviceMeta(ip, callback) {

    var base = "http://" + ip + "/dyn/load.jsn?file="

    var result = {}
    var done = 0

    function checkDone() {
        done++
        if (done === 3)
            callback(result)
    }

    fetchJSONWithRetry(base + "params.jsn", 5, 1000, function (d) {
        result.params = d
        checkDone()
    })

    fetchJSONWithRetry(base + "config.jsn", 5, 1000, function (d) {
        result.config = d
        checkDone()
    })

    fetchJSONWithRetry(base + "system.jsn", 5, 1000, function (d) {
        result.system = d
        checkDone()
    })
}

////////////////////////////

function fetchAllMeta(callback) {

    var result = {}
    var done = 0

    function checkDone() {
        done++
        if (done === 2)
            callback(result)
    }

    fetchDeviceMeta("192.168.144.213", function (d) {
        result.device_213 = d
        checkDone()
    })

    fetchDeviceMeta("192.168.144.136", function (d) {
        result.device_136 = d
        checkDone()
    })
}


property var lastMeasurement213: ""
property var lastMeasurement136: "" 

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



function fetchMeasurement(ip, callback) {
    var url = "http://" + ip + "/dyn/load.jsn?file=measurement.jsn"

    fetchJSONWithRetry(url, 3, 500, function (json) {
        if (!json) {
            callback(null, null)
            return
        }

        var raw = JSON.stringify(json)
        var flat = flattenMeasurement(json)

        callback(raw, flat)
    })
}


    function loadData() {

        var device213 = {}
        var device136 = {}

        var done1 = false
        var done2 = false

        function tryProcess() {
            if (done1 && done2) {

                // Only proceed if at least one device changed
                if (!device213.changed && !device136.changed) {
                    console.log("No measurement change → skip")
                    return
                }

                var d1 = device213.csv || []
                var d2 = device136.csv || []

                var result = computeSpectra(d1, d2)

                logger.logSpectrumExtended(
                    d1,
                    d2,
                    result.reflectance,
                    device213.meta,
                    device136.meta
                )

                updateChart(result)
            }
        }

        // --- DEVICE 213 ---
        fetchMeasurement("192.168.144.213", function (raw, flat) {

            if (!raw) {
                done1 = true
                tryProcess()
                return
            }

            var changed = (raw !== lastMeasurement213)

            device213.meta = flat
            device213.changed = changed

            if (changed) {
                lastMeasurement213 = raw

                fetchCSV("http://192.168.144.213/dyn/spectrum.csv?type=measure",
                    function (d) {
                        device213.csv = d
                        done1 = true
                        tryProcess()
                    })
            } else {
                device213.csv = null
                done1 = true
                tryProcess()
            }
        })

        // --- DEVICE 136 ---
        fetchMeasurement("192.168.144.136", function (raw, flat) {

            if (!raw) {
                done2 = true
                tryProcess()
                return
            }

            var changed = (raw !== lastMeasurement136)

            device136.meta = flat
            device136.changed = changed

            if (changed) {
                lastMeasurement136 = raw

                fetchCSV("http://192.168.144.136/dyn/spectrum.csv?type=measure",
                    function (d) {
                        device136.csv = d
                        done2 = true
                        tryProcess()
                    })
            } else {
                device136.csv = null
                done2 = true
                tryProcess()
            }
        })
    }


		    
	
    function fetchCSV(url, callback) {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    callback(parseCSV(xhr.responseText))
                } else {
                    console.log("Failed:", url)
                }
            }
        }
        xhr.open("GET", url)
        xhr.send()
    }

    function parseCSV(text) {
        var lines = text.split("\n")
        var result = []

        for (var i = 0; i < lines.length; i++) {
            if (!lines[i])
                continue
            var parts = lines[i].split(";")
            var x = Number(parts[0])
            var y = Number(parts[1])
            result.push({
                            "x": x,
                            "y": y
                        })
        }
        return result
    }
	
	
	function computeSpectra(data1, data2) {

		var radiance = []
		var irradiance = []
		var reflectance = []

		var minY1 = Number.POSITIVE_INFINITY
		var maxY1 = Number.NEGATIVE_INFINITY

		var minY2 = Number.POSITIVE_INFINITY
		var maxY2 = Number.NEGATIVE_INFINITY

		var minY3 = Number.POSITIVE_INFINITY
		var maxY3 = Number.NEGATIVE_INFINITY

		var has1 = data1.length > 0
		var has2 = data2.length > 0

		for (var i = 0; i < Math.max(data1.length, data2.length); i++) {

			var x = (has1 && data1[i]) ? data1[i].x :
					(has2 && data2[i]) ? data2[i].x : 0
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

	function updateChart(result) {

		radianceSeries.clear()
		irradianceSeries.clear()
		reflectanceSeries.clear()

		for (var i = 0; i < result.radiance.length; i++) {
			var p = result.radiance[i]
			radianceSeries.append(p.x, p.y)
		}

		for (var i = 0; i < result.irradiance.length; i++) {
			var p = result.irradiance[i]
			irradianceSeries.append(p.x, p.y)
		}

		for (var i = 0; i < result.reflectance.length; i++) {
			var p = result.reflectance[i]
			reflectanceSeries.append(p.x, p.y)
		}

		axisY1.min = result.axisY1.min
		axisY1.max = result.axisY1.max

		axisY2.min = result.axisY2.min
		axisY2.max = result.axisY2.max

		axisY3.min = result.axisY3.min
		axisY3.max = result.axisY3.max
	}
}
