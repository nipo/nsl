import platform, time
from colorama import init, Fore, Style
import readline
import atexit
from cbor_diag import diag2cbor

import socket

# UDP_SERVER = "udp/127.0.0.1:4242/datagram/"

UDP_HOST = "127.0.0.1"
UDP_PORT = 4242
UDP_SOCKET = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

def hex_string_to_bytes(hex_str):
    try:
        return bytes.fromhex(hex_str)
    except ValueError:
        print("Invalid hex input. Use format like: '01 ff a0'")
        return None

def hex_string_to_frame(hex_str):
    data = hex_string_to_bytes(hex_str)
    if data is not None:
        frame_length = len(data)
        data = frame_length.to_bytes(2, 'little') + data
    return data

def cbor_diag_to_frame(diagnostic_str):
    """
    Convert CBOR diagnostic string to a framed binary message with a 2-byte little-endian length header.
    """
    try:
        cbor_bytes = diag2cbor(diagnostic_str)
        frame = len(cbor_bytes).to_bytes(2, 'little') + cbor_bytes
        return frame
    except Exception as e:
        print(Fore.RED + f"Error parsing CBOR diagnostic input: {e}")
        return None

def cbor_diag_to_hex(diagnostic_str):
    """
    Convert CBOR diagnostic string to a list of bytes.
    """
    try:
        return diag2cbor(diagnostic_str)
    except Exception as e:
        print(Fore.RED + f"Error parsing CBOR diagnostic input: {e}")
        return None

def print_bytes_as_hex(data, received=True):
    hex_str = ' '.join(f'{b:02x}' for b in data)
    if received:
        print(Fore.GREEN + f"Received ({len(data)} bytes): {hex_str}")
    else:
        print(Fore.LIGHTBLUE_EX + f"Sent ({len(data)} bytes): {hex_str}")

def print_frame(data, initial_index, length):
    frame = data[initial_index:initial_index + length]
    hex_str = ' '.join(f'{b:02x}' for b in frame)
    print(Fore.GREEN + f"Received frame of length {length}: {hex_str}")

def print_bytes_as_frames(data):
    frame_length = 0
    frame_index = 0
    while frame_index < len(data):
        frame_length = (data[frame_index + 1] << 8) + data[frame_index]
        print_frame(data, frame_index + 2, frame_length)
        frame_index = frame_index + 2 + frame_length

def is_windows():
    return platform.system() == 'Windows'

def select_response_mode():
    while True:
        resp = input("Read responses from device? (y/n): ").strip().lower()
        if resp == 'y':
            return True
        elif resp == 'n':
            return False
        else:
            print("Please enter 'y' or 'n'.")

def read_frame(ser):
    header = ser.read(2)
    if len(header) < 2:
        return None
    length = int.from_bytes(header, byteorder="little")

    payload = b""
    while len(payload) < length:
        chunk = ser.read(length - len(payload))
        if not chunk:
            break
        payload += chunk

    if len(payload) < length:
        hex_str = ' '.join(f'{b:02x}' for b in payload)
        print(Fore.RED + f"Incomplete response of length {len(payload)} (should be {length}): {hex_str}")
        return None
    return header + payload

def main():
    load_history()
    init()

    # should use a udp server

    read_responses = select_response_mode()

    try:

        print("\nEnter data to send:")
        print(" - Hex bytes: e.g., '01 ff a0'")
        print(" - CBOR diagnostic: start with 'cbor:' followed by the diagnostic string., cbor:[[1,0],9(h'0000'), 8(1), null]")
        print(" - CBOR diagnostic routed to a transactor: start with 'cbor:N:' where N is the address of the transactor e.g., cbor:3:[[1,0],9(h'0000'), 8(1), null]")
        print(" - Commands: 'port' to switch device, 'exit' to quit.\n")

        while True:
            user_input = input(">>> ").strip()

            if user_input.lower() == 'exit':
                break

            # --- Handle CBOR diagnostic vs HEX input ---
            if user_input.lower().startswith("cbor_r:"):
                route = int(user_input[7])
                diag_str = user_input[9:].strip()
                print("cbor data", diag_str)
                data = cbor_diag_to_hex(diag_str)
                if data:
                    print(Fore.BLUE + f"CBOR diagnostic parsed, sending {len(data)} bytes to route {route}...")
                    print("CBOR payload: ", data)
                data = bytes([0xfd]) + int.to_bytes(route, byteorder='little', length=3) + data
                if data is not None:
                    frame_length = len(data)
                    data = frame_length.to_bytes(2, 'little') + data
            elif user_input.lower().startswith("cbor:"):
                diag_str = user_input[5:].strip()
                print("cbor data", diag_str)
                data = cbor_diag_to_hex(diag_str)
                if data:
                    print(Fore.BLUE + f"CBOR diagnostic parsed, sending {len(data)} bytes...")
                    print("CBOR payload: ", data)
            else:
                data = hex_string_to_frame(user_input)

            if data:
                UDP_SOCKET.sendto(data, (UDP_HOST, UDP_PORT))
                print(Fore.LIGHTBLUE_EX + f"Sent {len(data)} bytes to UDP {UDP_HOST}:{UDP_PORT}")
                print_bytes_as_hex(data, False)


                if read_responses:
                    # response = read_frame(ser_cmd)
                    # response = UDP_SOCKET.recvfrom(1);
                    # print_bytes_as_hex(response[0])
                    data_list = []
                    UDP_SOCKET.setblocking(False)
                    time.sleep(0.2)
                    while True:
                        try:
                            data, addr = UDP_SOCKET.recvfrom(1)  # read one datagram
                            data_list.append(data)
                        except BlockingIOError:
                            print("no more data available")
                            break
                    print(f"Received {len(data_list)} packets")
                    print(data_list)

            print(Style.RESET_ALL + "\n")

        print("Connection closed.")

    except KeyboardInterrupt:
        print("\nInterrupted by user. Exiting...")

# ---------- History Handling ----------
def save_history(history_file="mgmt_cli_history.txt"):
    try:
        readline.write_history_file(history_file)
    except Exception:
        pass

def load_history(history_file="mgmt_cli_history.txt"):
    try:
        readline.read_history_file(history_file)
    except FileNotFoundError:
        pass

if __name__ == '__main__':
    main()
    atexit.register(save_history)
