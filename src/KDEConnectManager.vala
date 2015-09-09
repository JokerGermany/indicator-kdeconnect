/* Copyright 2014 KDE Connect Indicator Developers
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */
namespace KDEConnectIndicator {
    public class KDEConnectManager {
        private DBusConnection conn;
        private SList<DeviceIndicator> device_list;
        private SList<uint> subs_identifier;

        public KDEConnectManager () {
            try {
                conn = Bus.get_sync (BusType.SESSION);
            } catch (Error e) {
                message (e.message);
            }

            int max_trying = 4;
            while (!is_daemon_running ()) {
                if (max_trying == 2)
                    run_kdeconnect_binary ();
                if (max_trying <= 0) {
                    show_no_service_daemon ();
                    return;
                }

                Thread.usleep (500);
                message ("retrying to find KDE Connect DBus service");
                max_trying--;
            }
            message ("KDE Connect daemon found");

            device_list = new SList<DeviceIndicator> ();
            populate_devices ();

            uint id;
            subs_identifier = new SList<uint> ();

            id = conn.signal_subscribe (
                    "org.kde.kdeconnect",
                    "org.kde.kdeconnect.daemon",
                    "deviceAdded",
                    "/modules/kdeconnect",
                    null,
                    DBusSignalFlags.NONE,
                    device_added_cb
                    );
            subs_identifier.append (id);

            id = conn.signal_subscribe (
                    "org.kde.kdeconnect",
                    "org.kde.kdeconnect.daemon",
                    "deviceRemoved",
                    "/modules/kdeconnect",
                    null,
                    DBusSignalFlags.NONE,
                    device_removed_cb
                    );
            subs_identifier.append (id);

            id = conn.signal_subscribe (
                    "org.kde.kdeconnect",
                    "org.kde.kdeconnect.daemon",
                    "deviceVisibilityChanged",
                    "/modules/kdeconnect",
                    null,
                    DBusSignalFlags.NONE,
                    device_visibility_changed_cb
                    );
            subs_identifier.append (id);

            try {
                conn.call_sync (
                        "org.kde.kdeconnect",
                        "/modules/kdeconnect",
                        "org.kde.kdeconnect.daemon",
                        "acquireDiscoveryMode",
                        new Variant ("(s)", "Indicator-KDEConnect"),
                        null,
                        DBusCallFlags.NONE,
                        -1,
                        null
                        );
            } catch (Error e) {
                message (e.message);
            }
        }
        ~KDEConnectManager () {
            try {
                conn.call_sync (
                        "org.kde.kdeconnect",
                        "/modules/kdeconnect",
                        "org.kde.kdeconnect.daemon",
                        "releaseDiscoveryMode",
                        new Variant ("(s)", "Indicator-KDEConnect"),
                        null,
                        DBusCallFlags.NONE,
                        -1,
                        null
                        );
            } catch (Error e) {
                message (e.message);
            }

            foreach (uint i in subs_identifier)
                conn.signal_unsubscribe (i);
        }

        public int get_devices_number () {
            return (int) device_list.length ();
        }


        private void show_no_service_daemon () {
            var msg = new Gtk.MessageDialog (
                    null, Gtk.DialogFlags.MODAL,
                    Gtk.MessageType.WARNING,
                    Gtk.ButtonsType.OK,
                    "cannot connect to KDE Connect DBus service"
                    );
            msg.response.connect(()=>{
                    msg.destroy();
                    GLib.Application.get_default ().quit_mainloop ();
                    });

            msg.show_all ();
            msg.run ();
        }
        private void run_kdeconnect_binary () {
            //TODO: shouldn't hardcode the path
            File f = File.new_for_path ("/usr/lib/libexec/kdeconnectd");
            if (f.query_exists ()) {
                try {
                    Process.spawn_command_line_sync (f.get_path ());
                } catch (Error e) {
                    message (e.message);
                }
            }
        }
        private bool is_daemon_running () {
            try {
                var device_proxy = new DBusProxy.sync (
                        conn,
                        DBusProxyFlags.NONE,
                        null,
                        "org.kde.kdeconnect",
                        "/modules/kdeconnect",
                        "org.kde.kdeconnect.daemon",
                        null
                        );
                return (device_proxy.get_name_owner () != null);
            } catch (Error e) {
                message (e.message);
            }

            return false;
        }
        private void populate_devices () {
            string[] devs = devices ();

            foreach (string dev in devs) {
                string path = "/modules/kdeconnect/devices/"+dev;
                var d = new DeviceIndicator (path);
                device_list.append (d);
            }

            if (device_list.length () == 0)
                message ("no paired device found, open KDE Connect in your phone to start pairing");
        }
        private void add_device (string path) {
            var d = new DeviceIndicator (path);
            device_list.append (d);
        }
        private void remove_device (string path) {
            foreach (DeviceIndicator d in device_list) {
                if (d.path == path) {
                    device_list.remove (d);
                    break;
                }
            }
        }
        private void distribute_visibility_changes (string id, bool visible) {
            foreach (DeviceIndicator d in device_list) {
                if (d.path.has_suffix (id)) {
                    d.device_visibility_changed (visible);
                    break;
                }
                message (d.path);
            }
        }
        private string[] devices (bool only_reachable = false) {
            string[] list = {};
            try {
                var return_variant = conn.call_sync (
                        "org.kde.kdeconnect",
                        "/modules/kdeconnect",
                        "org.kde.kdeconnect.daemon",
                        "devices",
                        new Variant ("(b)", only_reachable),
                        null,
                        DBusCallFlags.NONE,
                        -1,
                        null
                        );
                Variant i = return_variant.get_child_value (0);
                return i.dup_strv ();
            } catch (Error e) {
                message (e.message);
            }
            return list;
        }

        private void device_added_cb (DBusConnection con, string sender, string object,
                string interface, string signal_name, Variant parameter) {
            string param = parameter.get_child_value (0).get_string ();
            var path = "/modules/kdeconnect/devices/"+param;
            add_device (path);
            device_added (path);
        }
        private void device_removed_cb (DBusConnection con, string sender, string object,
                string interface, string signal_name, Variant parameter) {
            string param = parameter.get_child_value (0).get_string ();
            var path = "/modules/kdeconnect/devices/"+param;
            remove_device (path);
            device_added (path);
        }
        private void device_visibility_changed_cb (DBusConnection con, string sender, string object,
                string interface, string signal_name, Variant parameter) {
            string param = parameter.get_child_value (0).get_string ();
            bool v = parameter.get_child_value (1).get_boolean ();

            distribute_visibility_changes (param, v);
            device_visibility_changed (param, v);
        }

        public signal void device_added (string id);
        public signal void device_removed (string id);
        public signal void device_visibility_changed (string id, bool visible);
    }
}

