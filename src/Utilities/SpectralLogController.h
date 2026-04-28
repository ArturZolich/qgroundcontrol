#pragma once

#include <QObject>
#include <QFile>

class Vehicle;

class SpectralLogController : public QObject
{
    Q_OBJECT

public:
    explicit SpectralLogController(QObject* parent = nullptr);

    Q_INVOKABLE void setVehicle(Vehicle* vehicle);

    Q_INVOKABLE void startSession();
    Q_INVOKABLE void stopSession();
	Q_INVOKABLE void logSpectrum(const QVariantList& data1,
								const QVariantList& data2,
								const QVariantList& reflectance);
								

private:
    QString _createFilePath();
    void _writeHeader();

    Vehicle* _vehicle = nullptr;
    QFile _file;
    bool _sessionActive = false;
};


