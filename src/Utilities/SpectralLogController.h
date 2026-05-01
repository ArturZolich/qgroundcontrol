#pragma once

#include <QObject>
#include <QFile>
#include <QVariantList>
#include <QVariantMap>

// Include QGC's MAVLink wrapper so the compiler recognizes mavlink_message_t
#include "MAVLinkLib.h"

class Vehicle;

class SpectralLogController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool triggerActive READ triggerActive NOTIFY triggerActiveChanged)

public:
    explicit SpectralLogController(QObject* parent = nullptr);

    Q_INVOKABLE void setVehicle(Vehicle* vehicle);

    Q_INVOKABLE void startSession();
    Q_INVOKABLE void stopSession();
	Q_INVOKABLE void logSpectrum(
                                const QVariantList& data1,
                                const QVariantList& data2,
                                const QVariantList& reflectance,
                                const QVariantMap& meta1,
                                const QVariantMap& meta2);
    Q_INVOKABLE void saveMetaJSON(const QString& json);

    bool triggerActive() const { return _triggerActive; }

signals:
    void triggerActiveChanged();

private slots:
    // CHANGED: Listen to the raw MAVLink stream instead
    void _onMavlinkMessageReceived(const mavlink_message_t& message);

private:

    QString _createFilePath();
    void _writeHeader();

    Vehicle* _vehicle = nullptr;
    QFile _file;
    bool _sessionActive = false;

    bool _triggerActive = false;
    int _triggerThreshold = 1500;
};


