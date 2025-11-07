import subprocess
import threading
import time
from flask import Flask, Response, render_template_string

# --- Global variables for the single camera thread ---
global_frame = None  # The latest frame captured by the camera
global_frame_lock = threading.Lock()  # A lock to ensure thread-safe access to global_frame

TARGET_FPS = 30
FRAME_DURATION = 1.0 / TARGET_FPS

app = Flask(__name__)

HTML_TEMPLATE = """
<html>
<head>
    <title>RPi Cam Stream</title>
    <style>
        body { margin: 0; background: #333; }
        img { width: 100vw; height: 100vh; object-fit: contain; }
    </style>
</head>
<body>
    <img id="stream" src="/stream">
</body>
</html>
"""

# 2. This function runs in a single, separate thread
#    It's responsible for running rpicam-vid and updating the global_frame
def run_camera_thread():
    """
    Launches rpicam-vid and continuously updates the global_frame
    with the latest JPEG data. Restarts the process if it exits.
    """
    global global_frame, global_frame_lock
    
    print("Starting camera thread...")
    
    while True: 
        print("Launching rpicam-vid process...")
        
        cmd = [
            "rpicam-vid",
            "-t", "0",
            "--width", "640",
            "--height", "640",
            "--post-process-file", "/usr/share/rpi-camera-assets/hailo_yolov8_inference.json",
            "--codec", "mjpeg",
            "-o", "-"
        ]

        process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            
        print(f"Camera process started with PID: {process.pid}")

        jpeg_start = b'\xff\xd8'
        jpeg_end = b'\xff\xd9'
        frame_data = bytearray()
        
        try:
            while process.poll() is None:
                byte = process.stdout.read(1)
                if not byte:
                    break
                
                frame_data.append(byte[0])
                
                start_index = frame_data.find(jpeg_start)
                if start_index != -1:
                    end_index = frame_data.find(jpeg_end, start_index)
                    if end_index != -1:
                        # We have a full frame
                        frame = frame_data[start_index:end_index + 2]
                        
                        # --- THIS IS THE KEY CHANGE ---
                        # Acquire the lock and update the global frame
                        with global_frame_lock:
                            global_frame = frame
                        
                        # Clear the buffer
                        frame_data = frame_data[end_index + 2:]

        except Exception as e:
            print(f"Error while reading from rpicam-vid stdout: {e}")
            
        finally:
            if process.poll() is None:
                process.terminate()

            stderr_output = process.stderr.read()
            if stderr_output:
                print("!!!!!!!! rpicam-vid ERROR !!!!!!!!")
                print(stderr_output.decode('utf-8', errors='ignore'))
                print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
            
            print("rpicam-vid process stopped. Restarting...")
            # Brief pause before restarting
            time.sleep(1)


# 3. This is the generator function for each client
#    It just reads the global_frame
def generate_frames_for_client():
    """
    A generator function that yields frames to a single client.
    It reads from the global_frame variable.
    """
    global global_frame, global_frame_lock
    
    print("Client connected: Starting frame stream.")
    
    while True:
        try:
            # Wait for a new frame to be available
            # Sleep for the calculated frame duration
            time.sleep(FRAME_DURATION)
            
            local_frame_copy = None
            with global_frame_lock:
                if global_frame:
                    # Make a copy of the frame under the lock
                    local_frame_copy = global_frame
            
            if local_frame_copy:
                # Yield the frame to this client
                yield (b'--frame\r\n'
                       b'Content-Type: image/jpeg\r\n\r\n' + local_frame_copy + b'\r\n')

        except GeneratorExit:
            # This happens when the client disconnects
            print("Client disconnected.")
            break


# 4. Route for the UI (the HTML page)
@app.route('/')
def index():
    print("Request for /: Serving HTML")
    return render_template_string(HTML_TEMPLATE)

# 5. Route for the Stream
@app.route('/stream')
def stream():
    print("Request for /stream: Starting MJPEG stream for a new client.")
    # This returns a streaming response.
    # Each client gets their own instance of the generator.
    return Response(generate_frames_for_client(),
                    mimetype='multipart/x-mixed-replace; boundary=frame')

# 6. Run the Flask server
if __name__ == '__main__':
    # Start the single camera thread in the background
    # Set it as a 'daemon' so it exits when the main app exits
    camera_thread = threading.Thread(target=run_camera_thread)
    camera_thread.daemon = True
    camera_thread.start()
    
    print("Starting Flask server on http://0.0.0.0:8080")
    # threaded=True is necessary to handle multiple clients
    app.run(host='0.0.0.0', port=8080, threaded=True)