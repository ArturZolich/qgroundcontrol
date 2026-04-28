
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
		if (v) {
			logger.setVehicle(v)
		}

		logger.startSession()
	}
	
	Component.onDestruction: {
		logger.stopSession()
	}
	
    property Item pipView
    property Item pipState: chartPipState

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
        anchors.topMargin: toolbar.height
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

	function loadData() {
		var data1 = null
		var data2 = null

		var done1 = false
		var done2 = false

		function tryProcess() {
			if (done1 && done2) {

				var d1 = data1 || []
				var d2 = data2 || []

				var result = computeSpectra(d1, d2)

				// log once, using computed reflectance
				logger.logSpectrum(d1, d2, result.reflectance)

				// render
				updateChart(result)
			}
		}

		fetchCSV("http://192.168.144.213/dyn/spectrum.csv?type=measure",
			function (d) {
				data1 = d
				done1 = true
				tryProcess()
			})

		fetchCSV("http://192.168.144.136/dyn/spectrum.csv?type=measure",
			function (d) {
				data2 = d
				done2 = true
				tryProcess()
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
