**Русский** | [English](https://github.com/Nothingmaxxing/UserProfileMover/blob/main/.github/README.en.md)

<h1 align="center">UserProfileMover</h1>

<p align="center">Перенос данных сотрудника на новый ПК одной кнопкой</p>

<p align="center">
  <a href="https://github.com/Nothingmaxxing/UserProfileMover/releases/latest"><img src="https://img.shields.io/github/v/release/Nothingmaxxing/UserProfileMover" alt="Release"></a>
  <a href="https://github.com/Nothingmaxxing/UserProfileMover/actions/workflows/check.yml"><img src="https://img.shields.io/github/actions/workflow/status/Nothingmaxxing/UserProfileMover/check.yml?branch=main&label=checks" alt="Checks"></a>
  <a href="https://github.com/Nothingmaxxing/UserProfileMover/releases"><img src="https://img.shields.io/github/downloads/Nothingmaxxing/UserProfileMover/total" alt="Downloads"></a>
  <a href="https://github.com/Nothingmaxxing/UserProfileMover/blob/main/LICENSE"><img src="https://img.shields.io/github/license/Nothingmaxxing/UserProfileMover" alt="License"></a>
  <img src="https://img.shields.io/badge/PowerShell-5.1-5391FE" alt="PowerShell 5.1">
  <img src="https://img.shields.io/badge/Windows-10%20%7C%2011%20%7C%20Server-0078D6" alt="Windows 10 | 11 | Server">
</p>

**UserProfileMover** переносит данные сотрудника домена Active Directory со старого ПК на новый: рабочий стол, документы, загрузки, браузеры с сохранёнными паролями и подписи КриптоПро. Всё делается из одного окна на ПК администратора, без установки и без агентов на ПК сотрудников.

> [!IMPORTANT]
> В копиях лежат пароли браузеров и ключи электронных подписей. Храните их там, куда есть доступ только у администраторов, или включайте шифрование копий.

## Возможности

- **Перенести сразу**: если оба ПК включены, одна кнопка переносит всё со старого ПК на новый.
- **Через хранилище**: «Снять с ПК» сейчас, «Развернуть на ПК» потом, например после переустановки Windows. Хранилище: шара на NAS или файловом сервере, а если NAS нет, папка или USB-диск на ПК администратора.
- **Пароли браузеров без экспорта**: Яндекс Браузер, Chromium-Gost, Chrome, Edge, Firefox. Ключи DPAPI переезжают вместе с профилем: сотрудник открывает браузер, и всё на месте.
- **Подписи КриптоПро**: контейнеры «Директория» и «Реестр», личные сертификаты с ключами.
- **Шифрование копий**: 7-Zip, AES-256.
- **Акт переноса**: HTML с таблицей «что перенесено» и строками для подписи.
- **Старый ПК не меняется**: на нём ничего не удаляется и не правится.
- **Подробный журнал**: каждый шаг и каждый нескопированный файл с причиной.
- **Русский и английский интерфейс**, проверка новой версии на GitHub.

## Быстрый старт

1. Скачайте ZIP из [последнего релиза](https://github.com/Nothingmaxxing/UserProfileMover/releases/latest), распакуйте в папку, куда сотрудники не могут писать, и снимите блокировку: `Get-ChildItem -Recurse | Unblock-File` в этой папке.
2. Скопируйте `config.example.psd1` в `config.psd1` и укажите в нём `StoreRoot`: где хранить копии.
3. Запустите `profile-move.cmd` и введите доменную учётку администратора.

Нужны домен AD, Windows 10/11 или Windows Server с Windows PowerShell 5.1 и учётка с правами администратора на ПК сотрудников. RSAT не нужен.

Подробная инструкция: **[README.md](https://github.com/Nothingmaxxing/UserProfileMover/blob/main/README.md)**. Она же лежит в ZIP и открывается кнопкой «Инструкция» в окне.

## Поддержать проект

Если окно пригодилось, поставьте проекту ⭐. Ошибки и пожелания пишите в [Issues](https://github.com/Nothingmaxxing/UserProfileMover/issues).

## Лицензия

[MIT](https://github.com/Nothingmaxxing/UserProfileMover/blob/main/LICENSE): можно пользоваться, менять и распространять свободно.
