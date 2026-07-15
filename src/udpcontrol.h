/*
  Copyright © 2025 serialplot contributors

  This file is part of serialplot.

  serialplot is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  serialplot is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with serialplot.  If not, see <http://www.gnu.org/licenses/>.
*/

#ifndef UDPCONTROL_H
#define UDPCONTROL_H

#include <QWidget>
#include <QIODevice>
#include <QUdpSocket>
#include <QByteArray>
#include <QSettings>

namespace Ui {
class UdpControl;
}

/**
 * Sequential QIODevice that receives UDP datagrams and exposes them as a
 * continuous byte stream suitable for canReadLine()/readLine()-based readers.
 *
 * Call feedData() whenever a new datagram arrives; the device buffers the bytes
 * and emits readyRead() so AbstractReader::onDataReady() is triggered.
 */
class UdpLineDevice : public QIODevice
{
    Q_OBJECT
public:
    explicit UdpLineDevice(QObject* parent = nullptr);

    void feedData(const QByteArray& data);

    bool isSequential() const override { return true; }
    bool canReadLine() const override;
    qint64 bytesAvailable() const override;

protected:
    qint64 readData(char* data, qint64 maxSize) override;
    qint64 writeData(const char*, qint64) override { return -1; }

private:
    QByteArray _buf;
};

class UdpControl : public QWidget
{
    Q_OBJECT

public:
    explicit UdpControl(QWidget* parent = nullptr);
    ~UdpControl();

    /// The line-buffered device to pass to DataFormatPanel::setDevice().
    QIODevice* device();

    bool isBound() const;

    void saveSettings(QSettings* settings);
    void loadSettings(QSettings* settings);

signals:
    /// Emitted when the socket is bound (true) or unbound (false).
    void socketToggled(bool bound);

private:
    Ui::UdpControl* ui;
    QUdpSocket    _socket;
    UdpLineDevice _lineDevice;

    void toggleBind(bool bind);
    void onDatagramReady();
    void updateStatus();
};

#endif // UDPCONTROL_H
