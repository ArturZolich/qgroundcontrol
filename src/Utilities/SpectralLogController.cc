#include "SpectralLogController.h"

#include "Vehicle.h"
#include "SettingsManager.h"
#include "AppSettings.h"

#include <QDir>
#include <QDateTime>
#include <QTextStream>

SpectralLogController::SpectralLogController(QObject* parent)
    : QObject(parent)
{
}

void SpectralLogController::setVehicle(Vehicle* vehicle)
{
    _vehicle = vehicle;
}

QString SpectralLogController::_createFilePath()
{
    QString dirPath =
        SettingsManager::instance()->appSettings()->telemetrySavePath();

    QDir dir(dirPath);

    QString base =
        QDateTime::currentDateTime().toString("yyyy-MM-dd_hh-mm-ss");

    QString name = "spectrum_" + base + ".csv";

    int i = 1;
    while (dir.exists(name)) {
        name = QString("spectrum_%1.%2.csv").arg(base).arg(i++);
    }

    return dir.absoluteFilePath(name);
}


void SpectralLogController::startSession()
{
    if (_sessionActive) {
        return;
    }

    QString path = _createFilePath();

    _file.setFileName(path);

    if (!_file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        qWarning() << "Failed to open log file:" << _file.errorString();
        return;
    }

    //_writeHeader();
    _sessionActive = true;

    qDebug() << "Logging started:" << path;
}

void SpectralLogController::stopSession()
{
    if (!_sessionActive)
        return;

    _file.flush();
    _file.close();

    _sessionActive = false;

    qDebug() << "Logging stopped";
}

void SpectralLogController::logSpectrum(const QVariantList& data1,
                                        const QVariantList& data2,
								        const QVariantList& reflectance)
{
    if (!_sessionActive || !_vehicle)
        return;

    QTextStream s(&_file);
	
	bool armed = _vehicle->armed();
	QString mode = _vehicle->flightMode();

    auto coord = _vehicle->coordinate();

    double lat = coord.isValid() ? coord.latitude() : 0;
    double lon = coord.isValid() ? coord.longitude() : 0;
    double alt = coord.isValid() ? coord.altitude() : 0;

    double roll = _vehicle->roll() ? _vehicle->roll()->rawValue().toDouble() : 0;
    double pitch = _vehicle->pitch() ? _vehicle->pitch()->rawValue().toDouble() : 0;
    double yaw = _vehicle->heading() ? _vehicle->heading()->rawValue().toDouble() : 0;
	
	int satellites = 0;

	double hdop = std::numeric_limits<double>::quiet_NaN();
	double vdop = std::numeric_limits<double>::quiet_NaN();

	auto gpsFactGroup = _vehicle->gpsFactGroup();
	if (gpsFactGroup) {
	    if (gpsFactGroup->factExists("hdop")) {
             hdop = gpsFactGroup->getFact("hdop")->rawValue().toDouble();
        }	  
        if (gpsFactGroup->factExists("vdop")) {
             vdop = gpsFactGroup->getFact("vdop")->rawValue().toDouble();
        }
	    if (gpsFactGroup->factExists("count")) {
             satellites = gpsFactGroup->getFact("count")->rawValue().toInt();
        }
    }

    QString ts = QDateTime::currentDateTime().toString(Qt::ISODate);


	// --- VEHICLE HEADER ---
	s << "#VEHICLE,"
	  << "timestamp,armed,mode,lat,lon,alt,roll,pitch,yaw,satellites,hdop,vdop\n";

	// --- VEHICLE DATA ---
	s << "#DATA,"
	  << ts << ","
	  << (armed ? 1 : 0) << ","
	  << "\"" << mode << "\"" << ","
	  << lat << ","
	  << lon << ","
	  << alt << ","
	  << roll << ","
	  << pitch << ","
	  << yaw << ","
	  << satellites << ","
	  << hdop << ","
	  << vdop << "\n";

	// --- RADIOMETRIC DATA SIZES ---

	s << "#SIZES,"
	  << data1.size() << ","
	  << data2.size() << ","
	  << reflectance.size() << "\n";
	  
	// --- RADIANCE (data1) ---
	s << "#RADIANCE_X";
	for (int i = 0; i < data1.size(); i++) {
		auto p = data1[i].toMap();
		s << "," << p["x"].toDouble();
	}
	s << "\n";

	s << "#RADIANCE_Y";
	for (int i = 0; i < data1.size(); i++) {
		auto p = data1[i].toMap();
		s << "," << p["y"].toDouble();
	}
	s << "\n";


	// --- IRRADIANCE (data2) ---
	s << "#IRRADIANCE_X";
	for (int i = 0; i < data2.size(); i++) {
		auto p = data2[i].toMap();
		s << "," << p["x"].toDouble();
	}
	s << "\n";

	s << "#IRRADIANCE_Y";
	for (int i = 0; i < data2.size(); i++) {
		auto p = data2[i].toMap();
		s << "," << p["y"].toDouble();
	}
	s << "\n";


	// --- REFLECTANCE (computed) ---
	// --- REFLECTANCE_X ---
	s << "#REFLECTANCE_X";
	for (int i = 0; i < reflectance.size(); i++) {
		auto p = reflectance[i].toMap();
		s << "," << p["x"].toDouble();
	}
	s << "\n";

	// --- REFLECTANCE_Y ---
	s << "#REFLECTANCE_Y";
	for (int i = 0; i < reflectance.size(); i++) {
		auto p = reflectance[i].toMap();
		s << "," << p["y"].toDouble();
	}
	s << "\n";
  
	// --- optional separator between records ---
	//s << "\n";
	s << "#RECORD_END\n\n";

    // Optional: flush every call (safe, slightly slower)
    _file.flush();
}


