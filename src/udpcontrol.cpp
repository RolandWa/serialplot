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

#include "udpcontrol.h"
#include "ui_udpcontrol.h"

#include <QHostAddress>
#include <QNetworkDatagram>
#include <QtDebug>

#define SG_Udp          "Udp"
#define SG_Udp_Address  "bindAddress"
#define SG_Udp_Port     "port"

// ---------------------------------------------------------------------------
// UdpLineDevice
// ---------------------------------------------------------------------------

UdpLineDevice::UdpLineDevice(QObject* parent) : QIODevice(parent)
{
    open(QIODevice::ReadOnly);
}

void UdpLineDevice::feedData(const QByteArray& data)
{
    _buf.append(data);
    emit readyRead();
}

bool UdpLineDevice::canReadLine() const
{
    // Qt 6's base canReadLine() only checks its internal buffer, not _buf.
    // We must also check _buf so AsciiReader's canReadLine() loop works.
    return _buf.contains('\n') || QIODevice::canReadLine();
}

qint64 UdpLineDevice::bytesAvailable() const
{
    return _buf.size() + QIODevice::bytesAvailable();
}

qint64 UdpLineDevice::readData(char* data, qint64 maxSize)
{
    qint64 n = qMin(maxSize, (qint64)_buf.size());
    if (n > 0)
    {
        memcpy(data, _buf.constData(), n);
        _buf.remove(0, n);
    }
    return n;
}

// ---------------------------------------------------------------------------
// UdpControl
// ---------------------------------------------------------------------------

UdpControl::UdpControl(QWidget* parent) :
    QWidget(parent),
    ui(new Ui::UdpControl)
{
    ui->setupUi(this);

    connect(ui->pbBind, &QPushButton::toggled, this, &UdpControl::toggleBind);

    connect(&_socket, &QUdpSocket::readyRead, this, &UdpControl::onDatagramReady);

    connect(&_socket, &QUdpSocket::errorOccurred,
            [this](QAbstractSocket::SocketError)
            {
                ui->lbStatus->setText("Error: " + _socket.errorString());
                ui->pbBind->setChecked(false);
            });
}

UdpControl::~UdpControl()
{
    if (_socket.state() == QAbstractSocket::BoundState)
        _socket.close();
    delete ui;
}

QIODevice* UdpControl::device()
{
    return &_lineDevice;
}

bool UdpControl::isBound() const
{
    return _socket.state() == QAbstractSocket::BoundState;
}

void UdpControl::onDatagramReady()
{
    while (_socket.hasPendingDatagrams())
    {
        QByteArray datagram = _socket.receiveDatagram().data();
        qDebug() << "[UDP] rx:" << datagram.trimmed();
        _lineDevice.feedData(datagram);
    }
}

void UdpControl::toggleBind(bool bind)
{
    if (bind)
    {
        QHostAddress addr(ui->leBindAddress->text().trimmed());
        if (addr.isNull()) addr = QHostAddress::Any;
        quint16 port = static_cast<quint16>(ui->sbPort->value());

        if (_socket.bind(addr, port))
        {
            qDebug() << "[UDP] bound to" << addr.toString() << "port" << port;
            ui->leBindAddress->setEnabled(false);
            ui->sbPort->setEnabled(false);
            ui->pbBind->setText("Unbind");
            updateStatus();
            emit socketToggled(true);
        }
        else
        {
            qDebug() << "[UDP] bind failed:" << _socket.errorString();
            ui->lbStatus->setText("Bind failed: " + _socket.errorString());
            ui->pbBind->setChecked(false);
        }
    }
    else
    {
        _socket.close();
        ui->leBindAddress->setEnabled(true);
        ui->sbPort->setEnabled(true);
        ui->pbBind->setText("Bind");
        ui->lbStatus->setText("Not bound");
        emit socketToggled(false);
    }
}

void UdpControl::updateStatus()
{
    ui->lbStatus->setText(
        QString("Bound to %1:%2")
            .arg(_socket.localAddress().toString())
            .arg(_socket.localPort()));
}

void UdpControl::saveSettings(QSettings* settings)
{
    settings->beginGroup(SG_Udp);
    settings->setValue(SG_Udp_Address, ui->leBindAddress->text());
    settings->setValue(SG_Udp_Port, ui->sbPort->value());
    settings->endGroup();
}

void UdpControl::loadSettings(QSettings* settings)
{
    settings->beginGroup(SG_Udp);
    ui->leBindAddress->setText(settings->value(SG_Udp_Address, "0.0.0.0").toString());
    ui->sbPort->setValue(settings->value(SG_Udp_Port, 3000).toInt());
    settings->endGroup();
}
