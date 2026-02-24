

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
import QGroundControl.Controllers 1.0
import QGroundControl.ScreenTools 1.0

import QGroundControl.FlightDisplay 1.0

Item {
    id: _root
    //visible:    QGroundControl.videoManager.hasVideo

    /*
    property int    _track_rec_x:       0
    property int    _track_rec_y:       0
*/
    property Item pipState: chartPipState

    QGCPipState {
        id: chartPipState
        pipOverlay: _pipOverlay
        isDark: true

        onStateChanged: {
            _root.updateScreen()
        }
    }

    property var radianceData: []
    property var irradianceData: []
    property var reflectanceData: []


    ChartView {
        id: chartView
        anchors.fill: parent
        antialiasing: true
        title: "Calibrated Data"
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

/*
    function loadData() {
        fetchCSV("http://192.168.144.213/dyn/spectrum.csv?type=measure",
                 function (data1) {
                     fetchCSV("http://192.168.144.136/dyn/spectrum.csv?type=measure",
                              function (data2) {
                                  updateChart(data1, data2)
                              })
                 })
    }*/

    function loadData() {

        var file1 = "file:///C:/file1.csv"
        var file2 = "file:///C:/file2.csv"

        fetchCSV(file1, function(data1) {
            fetchCSV(file2, function(data2) {
                updateChart(data1, data2)
            })
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
    /*
    function updateChart(data1, data2) {
        radianceSeries.clear()
        irradianceSeries.clear()
        reflectanceSeries.clear()

        for (var i = 0; i < data1.length; i++) {
            var x = data1[i].x
            var y1 = data1[i].y
            var y2 = data2[i] ? data2[i].y : 0

            radianceSeries.append(x, y1)
            irradianceSeries.append(x, y2)

            if (y2 !== 0)
                reflectanceSeries.append(x, y1 / y2)
        }
    }
    */
    function updateChart(data1, data2) {

        radianceSeries.clear()
        irradianceSeries.clear()
        reflectanceSeries.clear()

        var minY1 = Number.POSITIVE_INFINITY
        var maxY1 = Number.NEGATIVE_INFINITY

        var minY2 = Number.POSITIVE_INFINITY
        var maxY2 = Number.NEGATIVE_INFINITY

        var minY3 = Number.POSITIVE_INFINITY
        var maxY3 = Number.NEGATIVE_INFINITY

        for (var i = 0; i < data1.length; i++) {

            var x = data1[i].x
            var y1 = data1[i].y
            var y2 = data2[i] ? data2[i].y : 0

            radianceSeries.append(x, y1)
            irradianceSeries.append(x, y2)

            // Track Radiance min/max
            if (y1 < minY1) minY1 = y1
            if (y1 > maxY1) maxY1 = y1

            // Track Irradiance min/max
            if (y2 < minY2) minY2 = y2
            if (y2 > maxY2) maxY2 = y2

            if (y2 !== 0) {
                var rrs = y1 / y2
                reflectanceSeries.append(x, rrs)

                if (rrs < minY3) minY3 = rrs
                if (rrs > maxY3) maxY3 = rrs
            }
        }

        // Add small margin (5%)
        function addMargin(minVal, maxVal) {
            var range = maxVal - minVal
            return {
                min: minVal - range * 0.05,
                max: maxVal + range * 0.05
            }
        }

        var r1 = addMargin(minY1, maxY1)
        var r2 = addMargin(minY2, maxY2)
        var r3 = addMargin(minY3, maxY3)

        axisY1.min = r1.min
        axisY1.max = r1.max

        axisY2.min = r2.min
        axisY2.max = r2.max

        axisY3.min = r3.min
        axisY3.max = r3.max
    }

}
