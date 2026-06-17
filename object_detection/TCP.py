import rclpy
from rclpy.node import Node

import socket
import threading
import json
import struct


class TCPServer(Node):
    def __init__(self):
        super().__init__('telemetry_receiver')

        self.host = '0.0.0.0'
        self.port = 7003

        self.server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server.bind((self.host, self.port))
        self.server.listen(1)

        self.get_logger().info(f"Waiting TCP connection on {self.port}...")

        self.conn, self.addr = self.server.accept()
        self.get_logger().info(f"Connected: {self.addr}")

        self.buffer = b""

        self.latest_json = None
        self.latest_image_bytes = None

        self.thread = threading.Thread(target=self.loop, daemon=True)
        self.thread.start()


    def loop(self):
        while True:
            try:
                data = self.conn.recv(65536)

                if not data:
                    self.get_logger().info("Client disconnected")
                    break

                self.buffer += data

                while True:
                    # JSON
                    if len(self.buffer) < 4:
                        break

                    json_len = struct.unpack(">I", self.buffer[:4])[0]

                    if len(self.buffer) < 4 + json_len + 4:
                        break

                    json_start = 4
                    json_end = 4 + json_len

                    json_bytes = self.buffer[json_start:json_end]
                    
                    # Image
                    image_len = struct.unpack(">I", self.buffer[json_end:json_end+4])[0]

                    total_len = 4 + json_len + 4 + image_len

                    if len(self.buffer) < total_len:
                        break

                    image_start = json_end + 4
                    image_end = image_start + image_len
                
                    image_bytes = self.buffer[image_start:image_end]

                    self.buffer = self.buffer[total_len:]

                    obj = json.loads(json_bytes.decode())

                    self.latest_json = obj
                    # Use `self.latest_image_bytes` to restore an image
                    self.latest_image_bytes = image_bytes

                    # Display data for debugging
                    # You can retrieve the necessary data using `obj.get('')` or `d['']`.
                    self.get_logger().info("=== FRAME RECEIVED ===")
                    self.get_logger().info(f"fps: {obj.get('fps')}")
                    self.get_logger().info(f"detections: {len(obj.get('detections', []))}")

                    for d in obj.get("detections", []):
                        self.get_logger().info(
                            f"class={d['objectClass']} "
                            f"conf={d['confidence']:.2f} "
                            f"normX={d['normX']:.3f} "
                            f"normY={d['normY']:.3f}"
                        )
                    
                    hex_str = image_bytes.hex()
                    self.get_logger().info(f"Image (hex): {hex_str}")
                    self.get_logger().info(f"Image bytes: {len(image_bytes)}")

            except Exception as e:
                self.get_logger().error(f"Socket error: {e}")
                break


def main(args=None):
    rclpy.init(args=args)
    node = TCPServer()
    rclpy.spin(node)

    node.destroy_node()
    rclpy.shutdown()

if __name__ == '__main__':
    main()