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
    if (_vehicle) {
        // Disconnect the old vehicle's MAVLink stream
        disconnect(_vehicle, &Vehicle::mavlinkMessageReceived, this, &SpectralLogController::_onMavlinkMessageReceived);
    }

    _vehicle = vehicle;

    if (_vehicle) {
        // Connect the new vehicle's MAVLink stream
        connect(_vehicle, &Vehicle::mavlinkMessageReceived, this, &SpectralLogController::_onMavlinkMessageReceived);
    }
}

void SpectralLogController::_onMavlinkMessageReceived(const mavlink_message_t& message)
{
    // Filter out everything except the RC_CHANNELS message
    if (message.msgid == MAVLINK_MSG_ID_RC_CHANNELS) {

        mavlink_rc_channels_t rc;
        mavlink_msg_rc_channels_decode(&message, &rc);

        // MAVLink explicitly defines variables for 18 channels.
        // If you mapped your switch to Channel 8, we look at chan8_raw.
        // A value of 0 or 65535 usually means the channel is inactive/unplugged.
        int pwm = rc.chan11_raw;

        // Safely check if the channel is active and above our switch threshold
        bool isActive = (pwm > _triggerThreshold && pwm < 2500);

        // Only trigger UI updates/signals if the state actually flipped
        if (isActive != _triggerActive) {
            _triggerActive = isActive;
            emit triggerActiveChanged();

            // Optional: Good for debugging on the bench
            qDebug() << "RC Trigger changed state to:" << _triggerActive << "PWM:" << pwm;
        }
    }
}


void SpectralLogController::saveMetaJSON(const QString& json)
{
    if (!_sessionActive)
        return;

    QString path = _file.fileName();

    QString metaPath = path;
    metaPath.replace(".csv", "_meta.json");

    QFile f(metaPath);

    if (!f.open(QIODevice::WriteOnly | QIODevice::Text)) {
        qWarning() << "Failed to write meta JSON:" << f.errorString();
        return;
    }

    f.write(json.toUtf8());
    f.close();

    qDebug() << "Saved meta JSON:" << metaPath;
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
                                        const QVariantList& reflectance,
                                        const QVariantMap& meta1,
                                        const QVariantMap& meta2)
{
    // ONLY check for session active. Do not block if _vehicle is null.
    if (!_sessionActive)
        return;

    QTextStream s(&_file);
    QString ts = QDateTime::currentDateTime().toString(Qt::ISODate);

            // 1. Setup default values (used if no vehicle is connected)
    bool armed = false;
    QString mode = "UNKNOWN";
    double lat = 0, lon = 0, alt = 0;
    double roll = 0, pitch = 0, yaw = 0;
    int satellites = 0;
    double hdop = std::numeric_limits<double>::quiet_NaN();
    double vdop = std::numeric_limits<double>::quiet_NaN();

            // 2. Safely extract vehicle data ONLY if _vehicle is valid
    if (_vehicle) {
        armed = _vehicle->armed();
        mode = _vehicle->flightMode();

        auto coord = _vehicle->coordinate();
        lat = coord.isValid() ? coord.latitude() : 0;
        lon = coord.isValid() ? coord.longitude() : 0;
        alt = coord.isValid() ? coord.altitude() : 0;

        roll = _vehicle->roll() ? _vehicle->roll()->rawValue().toDouble() : 0;
        pitch = _vehicle->pitch() ? _vehicle->pitch()->rawValue().toDouble() : 0;
        yaw = _vehicle->heading() ? _vehicle->heading()->rawValue().toDouble() : 0;

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
    }

    // --- VEHICLE HEADER ---
    // Added 'rc_trigger' to the end of the header
    s << "#VEHICLE,"
      << "timestamp,armed,mode,lat,lon,alt,roll,pitch,yaw,satellites,hdop,vdop,rc_trigger\n";

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
      << vdop << ","
      << (_triggerActive ? 1 : 0) << "\n"; // 1 if switch is flipped, 0 if not

            // --- RADIOMETRIC METADATA ---
    s << "#RADIANCE_METADATA";
    for (auto it = meta1.begin(); it != meta1.end(); ++it) {
        s << "," << it.key() << "=" << it.value().toString();
    }
    s << "\n";

    s << "#IRRADIANCE_METADATA";
    for (auto it = meta2.begin(); it != meta2.end(); ++it) {
        s << "," << it.key() << "=" << it.value().toString();
    }
    s << "\n";

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
    s << "#REFLECTANCE_X";
    for (int i = 0; i < reflectance.size(); i++) {
        auto p = reflectance[i].toMap();
        s << "," << p["x"].toDouble();
    }
    s << "\n";

    s << "#REFLECTANCE_Y";
    for (int i = 0; i < reflectance.size(); i++) {
        auto p = reflectance[i].toMap();
        s << "," << p["y"].toDouble();
    }
    s << "\n";

            // --- RECORD END ---
    s << "#RECORD_END\n\n";

    _file.flush();
}

