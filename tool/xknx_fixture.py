"""Builds the synthetic XKNX Editor projects (.xknx) for test/xknx_parser_test.dart.

Call: python3 tool/xknx_fixture.py   (needs the Python package "cryptography")

The tables follow the editor's schema (xknx-editor 0.11, SQLite user_version 5), reduced to the
columns Busclear reads plus a few it ignores. No data of a real installation.
"""
import base64
import hashlib
import os
import sqlite3

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

OUT = os.path.join(os.path.dirname(__file__), '..', 'test', 'fixtures', 'xknx')
PASSWORD = 'geheim'

SCHEMA = """
CREATE TABLE projects (
	id VARCHAR NOT NULL, name TEXT NOT NULL, group_address_style VARCHAR NOT NULL,
	guid VARCHAR, knx_master_xml BLOB, password_salt VARCHAR, password_check VARCHAR,
	PRIMARY KEY (id)
);
CREATE TABLE areas (id INTEGER NOT NULL, installation_id INTEGER NOT NULL, address INTEGER NOT NULL,
	name TEXT NOT NULL, PRIMARY KEY (id));
CREATE TABLE lines (id INTEGER NOT NULL, area_id INTEGER NOT NULL, address INTEGER NOT NULL,
	name TEXT NOT NULL, PRIMARY KEY (id), FOREIGN KEY(area_id) REFERENCES areas (id));
CREATE TABLE segments (id INTEGER NOT NULL, line_id INTEGER NOT NULL, number INTEGER NOT NULL,
	medium_type VARCHAR NOT NULL, PRIMARY KEY (id));
CREATE TABLE spaces (id INTEGER NOT NULL, installation_id INTEGER NOT NULL, parent_id INTEGER,
	space_type VARCHAR NOT NULL, name TEXT NOT NULL, "order" INTEGER, PRIMARY KEY (id));
CREATE TABLE devices (
	id INTEGER NOT NULL, segment_id INTEGER, address INTEGER, name TEXT NOT NULL,
	product_ref_id VARCHAR, space_id INTEGER, description TEXT NOT NULL, serial_number VARCHAR,
	last_download VARCHAR, order_number VARCHAR, hardware_name TEXT, product_name TEXT,
	manufacturer_name TEXT, individual_address_loaded BOOLEAN, application_program_loaded BOOLEAN,
	communication_part_loaded BOOLEAN, medium_config_loaded BOOLEAN, parameters_loaded BOOLEAN,
	PRIMARY KEY (id)
);
CREATE TABLE device_additional_addresses (id INTEGER NOT NULL, device_id INTEGER NOT NULL,
	address INTEGER NOT NULL, name TEXT NOT NULL, PRIMARY KEY (id));
CREATE TABLE group_ranges (id INTEGER NOT NULL, installation_id INTEGER NOT NULL, parent_id INTEGER,
	range_start INTEGER NOT NULL, range_end INTEGER NOT NULL, name TEXT NOT NULL, PRIMARY KEY (id));
CREATE TABLE group_addresses (
	id INTEGER NOT NULL, group_range_id INTEGER NOT NULL, address INTEGER NOT NULL, name TEXT NOT NULL,
	datapoint_type VARCHAR, description TEXT NOT NULL, security_key VARCHAR, PRIMARY KEY (id)
);
CREATE TABLE com_objects (
	id INTEGER NOT NULL, device_id INTEGER NOT NULL, ref_id VARCHAR NOT NULL,
	read_flag BOOLEAN, write_flag BOOLEAN, communication_flag BOOLEAN, transmit_flag BOOLEAN,
	update_flag BOOLEAN, read_flag_override BOOLEAN, write_flag_override BOOLEAN,
	communication_flag_override BOOLEAN, transmit_flag_override BOOLEAN, update_flag_override BOOLEAN,
	text_override TEXT, function_text_override TEXT, datapoint_type_override VARCHAR, PRIMARY KEY (id)
);
CREATE TABLE com_object_links (id INTEGER NOT NULL, com_object_id INTEGER NOT NULL,
	group_address_id INTEGER NOT NULL, is_sending BOOLEAN NOT NULL, PRIMARY KEY (id));
CREATE INDEX ix_links_ga ON com_object_links (group_address_id);
"""

APP_ACT = 'M-0083_A-0001-10-AAAA'
APP_BTN = 'M-0083_A-0002-10-BBBB'


def ga(main, middle, sub):
    return (main << 11) | (middle << 8) | sub


def build(path, protected):
    if os.path.exists(path):
        os.remove(path)
    db = sqlite3.connect(path)
    db.executescript(SCHEMA)
    salt = check = None
    if protected:
        raw = b'0123456789abcdef'
        salt = f'pbkdf2-sha256:1000:{base64.b64encode(raw).decode()}'
        key = hashlib.pbkdf2_hmac('sha256', PASSWORD.encode(), raw, 1000)
        nonce = b'\x01' * 12
        sealed = AESGCM(key).encrypt(nonce, b'xknx-editor project password', b'xknx-editor/enc1')
        check = 'enc1:' + base64.b64encode(nonce + sealed).decode()
    db.execute("INSERT INTO projects VALUES ('P-0001','Testhaus','ThreeLevel','g',?,?,?)", (b'\0' * 2000, salt, check))
    db.execute("INSERT INTO areas VALUES (1,1,1,'Bereich 1')")
    db.execute("INSERT INTO lines VALUES (1,1,1,'Linie 1.1')")
    db.execute("INSERT INTO segments VALUES (1,1,0,'TP')")
    db.executemany('INSERT INTO spaces VALUES (?,?,?,?,?,?)', [
        (1, 1, None, 'Building', 'Haus', 0),
        (2, 1, 1, 'Floor', 'EG', 0),
        (3, 1, 2, 'Room', 'Küche', 0),
    ])
    serial = base64.b64encode(bytes.fromhex('0083AABBCCDD')).decode()
    loaded = (1, 1, 1, 1, 1)
    db.executemany('INSERT INTO devices VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)', [
        (1, 1, 10, '', 'M-0083_H-1_P-ACT', 3, 'Schrank', serial, '2026-10-17T14:24:40Z', 'ACT-1', 'Aktor', 'Schaltaktor 4-fach', 'MDT technologies', *loaded),
        # Changed after the download: parameters and group communication pending.
        (2, 1, 20, 'Taster Küche', 'M-0083_H-2_P-BTN', 3, '', None, '2026-10-17T14:30:00Z', 'BTN-1', 'Taster', 'Taster 4-fach', 'MDT technologies', 1, 1, 0, 1, 0),
        (3, 1, 30, '', 'M-0083_H-3_P-BIN', None, '', None, None, 'BE-1', 'Binäreingang', 'Binäreingang 2-fach', 'MDT technologies', 0, 0, 0, 0, 0),
        (4, None, None, '', 'M-0083_H-4_P-PS', None, '', None, None, 'PS-1', 'Netzteil', 'Spannungsversorgung', 'MDT technologies', 0, 0, 0, 0, 0),
        (5, 1, 40, 'IP-Router', 'M-0008_H-5_P-IP', None, '', None, '2026-10-01T08:00:00Z', 'IP-1', 'IP', 'IP-Schnittstelle', 'GIRA Giersiepen', *loaded),
    ])
    db.execute("INSERT INTO device_additional_addresses VALUES (1,5,200,'Tunnel A')")
    db.execute("INSERT INTO device_additional_addresses VALUES (2,5,201,'')")
    db.executemany('INSERT INTO group_ranges VALUES (?,?,?,?,?,?)', [
        (1, 1, None, ga(1, 0, 0), ga(1, 7, 255), 'Licht'),
        (2, 1, 1, ga(1, 1, 0), ga(1, 1, 255), 'Schalten'),
        (3, 1, 1, ga(1, 4, 0), ga(1, 4, 255), 'Rückmeldung'),
        (4, 1, None, ga(8, 0, 0), ga(8, 7, 255), 'Diverses'),
        (5, 1, 4, ga(8, 1, 0), ga(8, 1, 255), 'Viele'),
    ])
    long_text = 'Sehr lange Beschreibung. ' * 300  # forces an overflow page
    rows = [
        (1, 2, ga(1, 1, 0), 'Küche Licht Schalten', 'DPST-1-1', long_text, None),
        (2, 3, ga(1, 4, 0), 'Küche Licht Rückmeldung', None, '', None),
        (3, 2, ga(1, 1, 1), 'Ohne Verknüpfung', 'DPST-1-1', '', 'enc1:AAAA'),
    ]
    # Enough rows for interior b-tree pages.
    rows += [(10 + i, 5, ga(8, 1, i), f'Adresse {i:03d} ' + 'x' * 40, 'DPST-9-1', '', None) for i in range(256)]
    db.executemany('INSERT INTO group_addresses VALUES (?,?,?,?,?,?,?)', rows)
    db.executemany('INSERT INTO com_objects VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)', [
        # Actuator: switch input (C W), status output (C R T)
        (1, 1, f'{APP_ACT}_O-0_R-1', 0, 1, 1, 0, 0, None, None, None, None, None, None, None, None),
        (2, 1, f'{APP_ACT}_O-1_R-2', 1, 0, 1, 1, 0, None, None, None, None, None, None, None, 'DPST-1-1'),
        # Push button: switch output (C T), status display (C W T U: an input, does not send)
        (3, 2, f'{APP_BTN}_MD-1_M-1_MI-1_O-3-0_R-5', 0, 0, 1, 1, 0, None, None, None, None, None, 'Taste 1', 'Licht', None),
        (4, 2, f'{APP_BTN}_O-9_R-9', 0, 1, 1, 1, 1, None, None, None, None, None, None, None, None),
        # Override: application says C R T, project switches T off.
        (5, 1, f'{APP_ACT}_O-2_R-3', 1, 0, 1, 1, 0, None, None, None, 0, None, None, None, None),
    ])
    db.executemany('INSERT INTO com_object_links VALUES (?,?,?,?)', [
        (1, 1, 1, 1),  # actuator input, first address but no T
        (2, 3, 1, 1),  # push button sends 1/1/0
        (3, 2, 2, 1),  # actuator status sends 1/4/0
        (4, 4, 2, 1),  # push button display listens to 1/4/0
        (5, 5, 2, 1),  # transmit switched off by override
    ] + [(10 + i, 2, 10 + i, 0) for i in range(256)])
    db.commit()
    db.execute('PRAGMA user_version = 5')
    db.close()


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    build(os.path.join(OUT, 'testhaus.xknx'), protected=False)
    build(os.path.join(OUT, 'testhaus_passwort.xknx'), protected=True)
    print('fixtures written to', os.path.normpath(OUT))
