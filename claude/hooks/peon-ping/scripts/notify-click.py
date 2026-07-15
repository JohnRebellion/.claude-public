#!/usr/bin/env python3
"""peon-ping: send a notification with body-click activation.

Sends a desktop notification via the org.freedesktop.Notifications D-Bus
service with a `default` action (FreeDesktop convention for body-click) plus
an explicit `open` button. Listens for ActionInvoked on the returned ID and
runs the focus script when triggered.

Designed to be launched in the background — exits after the notification is
closed or activated.

Usage:
    notify-click.py <title> <body> [icon_path] [dismiss_secs] [focus_cwd] [focus_script]

Exit codes:
    0 on success (notification shown — click may or may not have happened)
    >0 on D-Bus error
"""
from __future__ import annotations

import os
import subprocess
import sys
import time

import dbus
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib


APP_NAME = "peon-ping"
NOTIF_IFACE = "org.freedesktop.Notifications"
NOTIF_PATH = "/org/freedesktop/Notifications"


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: notify-click.py <title> <body> [icon] [dismiss] [cwd] [script]", file=sys.stderr)
        return 2

    title = sys.argv[1]
    body = sys.argv[2]
    icon = sys.argv[3] if len(sys.argv) > 3 else ""
    try:
        dismiss_secs = int(sys.argv[4]) if len(sys.argv) > 4 else 4
    except ValueError:
        dismiss_secs = 4
    focus_cwd = sys.argv[5] if len(sys.argv) > 5 else ""
    focus_script = sys.argv[6] if len(sys.argv) > 6 else ""

    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    try:
        notif = bus.get_object(NOTIF_IFACE, NOTIF_PATH)
        iface = dbus.Interface(notif, NOTIF_IFACE)
    except dbus.DBusException as exc:
        print(f"dbus connect failed: {exc}", file=sys.stderr)
        return 1

    actions = dbus.Array(
        ["default", "Open in VS Code", "open", "Open in VS Code"],
        signature="s",
    )
    hints: dict = {
        "urgency": dbus.Byte(1),
        "x-kde-origin-name": APP_NAME,
    }
    expire_ms = dismiss_secs * 1000 if dismiss_secs > 0 else 0

    try:
        notif_id = iface.Notify(
            APP_NAME,
            dbus.UInt32(0),
            icon or "",
            title,
            body,
            actions,
            hints,
            dbus.Int32(expire_ms),
        )
    except dbus.DBusException as exc:
        print(f"Notify failed: {exc}", file=sys.stderr)
        return 1

    loop = GLib.MainLoop()
    state = {"acted": False}

    def on_action(nid, action_key):
        if int(nid) != int(notif_id):
            return
        state["acted"] = True
        if focus_cwd and focus_script and os.path.isfile(focus_script):
            try:
                subprocess.Popen(
                    [focus_script, focus_cwd],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    start_new_session=True,
                )
            except Exception as exc:
                print(f"focus exec failed: {exc}", file=sys.stderr)
        loop.quit()

    def on_closed(nid, reason):
        if int(nid) != int(notif_id):
            return
        if not state["acted"]:
            loop.quit()

    bus.add_signal_receiver(
        on_action,
        signal_name="ActionInvoked",
        dbus_interface=NOTIF_IFACE,
        path=NOTIF_PATH,
    )
    bus.add_signal_receiver(
        on_closed,
        signal_name="NotificationClosed",
        dbus_interface=NOTIF_IFACE,
        path=NOTIF_PATH,
    )

    # Safety timeout: never linger more than dismiss + 60s.
    safety = max(expire_ms, 4000) + 60_000
    GLib.timeout_add(safety, lambda: (loop.quit(), False)[1])

    try:
        loop.run()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
