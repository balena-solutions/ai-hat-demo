import subprocess
import threading
import time
import os
import cv2
import numpy as np
from flask import Flask, Response, render_template_string

# Hailo imports
try:
    from hailo_platform import (HEF, VDevice, HailoStreamInterface, 
                                 InferVStreams, ConfigureParams,
                                 InputVStreamParams, OutputVStreamParams)
    HAILO_AVAILABLE = True
except ImportError:
    HAILO_AVAILABLE = False
    print("Warning: Hailo platform not available")

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

# Hailo YOLOv8 inference helper functions
def preprocess_frame_for_hailo(frame, input_height, input_width):
    """
    Preprocess frame for Hailo inference.
    Resize and normalize according to model requirements.
    """
    resized = cv2.resize(frame, (input_width, input_height))
    # Convert BGR to RGB
    rgb_frame = cv2.cvtColor(resized, cv2.COLOR_BGR2RGB)
    # Normalize to 0-1 range (typical for YOLOv8)
    normalized = rgb_frame.astype(np.float32) / 255.0
    return normalized

def postprocess_yolov8_hailo(output, frame, conf_threshold=0.25, iou_threshold=0.45):
    """
    Post-process YOLOv8 Hailo output and draw bounding boxes on frame.
    This is a simplified version - you may need to adjust based on your specific model output format.
    """
    # The exact post-processing depends on your YOLOv8 model's output format
    # This is a generic implementation that may need adjustment
    
    # Typically YOLOv8 outputs shape like (1, 84, 8400) for COCO dataset
    # Where 84 = 4 (bbox) + 80 (classes)
    
    # Parse detections and draw on frame
    height, width = frame.shape[:2]
    
    # Apply NMS and draw boxes (simplified - adjust based on actual output format)
    # For now, just return the frame as-is
    # You'll need to implement proper parsing based on your model
    
    return frame

def draw_detections(frame, boxes, scores, class_ids, class_names=None):
    """
    Draw bounding boxes and labels on frame.
    """
    for box, score, class_id in zip(boxes, scores, class_ids):
        x1, y1, x2, y2 = box
        color = (0, 255, 0)  # Green boxes
        cv2.rectangle(frame, (int(x1), int(y1)), (int(x2), int(y2)), color, 2)
        
        label = f"Class {class_id}: {score:.2f}"
        if class_names and class_id < len(class_names):
            label = f"{class_names[class_id]}: {score:.2f}"
        
        cv2.putText(frame, label, (int(x1), int(y1) - 10),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 2)
    
    return frame

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


def run_camera_thread_usb(camera_index=0):
    """
    Uses OpenCV to capture frames from a USB camera and continuously 
    updates the global_frame with the latest JPEG data.
    """
    global global_frame, global_frame_lock
    
    print("Starting USB camera thread...")
    
    while True:
        print(f"Opening USB camera at index {camera_index}...")
        
        # Open the camera using OpenCV
        cap = cv2.VideoCapture(camera_index)
        
        if not cap.isOpened():
            print(f"Error: Could not open camera at index {camera_index}")
            time.sleep(5)  # Wait before retrying
            continue
        
        # Set camera properties (optional)
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 640)
        cap.set(cv2.CAP_PROP_FPS, TARGET_FPS)
        
        print(f"USB camera opened successfully")
        
        try:
            while True:
                ret, frame = cap.read()
                
                if not ret:
                    print("Error: Failed to read frame from camera")
                    break
                
                # Encode the frame as JPEG
                ret, jpeg = cv2.imencode('.jpg', frame)
                
                if not ret:
                    print("Error: Failed to encode frame as JPEG")
                    continue
                
                # Convert to bytes
                frame_bytes = jpeg.tobytes()
                
                # Update the global frame
                with global_frame_lock:
                    global_frame = frame_bytes
                
                # Control frame rate
                time.sleep(FRAME_DURATION)
                
        except Exception as e:
            print(f"Error while capturing from USB camera: {e}")
            
        finally:
            cap.release()
            print("USB camera released. Restarting...")
            time.sleep(1)


def run_camera_thread_usb_with_hailo(camera_index=0, hef_path="/usr/share/hailo-models/yolov8s_h8l.hef"):
    """
    Uses OpenCV to capture frames from a USB camera, runs Hailo inference,
    and continuously updates the global_frame with the latest JPEG data with bounding boxes.
    """
    global global_frame, global_frame_lock
    
    print("Starting USB camera thread with Hailo inference...")
    
    if not HAILO_AVAILABLE:
        print("ERROR: Hailo platform not available. Falling back to USB camera without inference.")
        return run_camera_thread_usb(camera_index)
    
    # Initialize Hailo device and model
    hailo_device = None
    infer_pipeline = None
    
    try:
        print(f"Loading Hailo model from {hef_path}...")
        hef = HEF(hef_path)
        
        # Get target device
        target = VDevice()
        
        # Configure the inference
        configure_params = ConfigureParams.create_from_hef(hef, interface=HailoStreamInterface.PCIe)
        network_group = target.configure(hef, configure_params)[0]
        network_group_params = network_group.create_params()
        
        # Get input/output stream parameters directly from the network group
        input_vstream_infos = hef.get_input_vstream_infos()
        output_vstream_infos = hef.get_output_vstream_infos()
        
        # Create vstream params
        input_vstreams_params = InputVStreamParams.make_from_network_group(network_group, quantized=False)
        output_vstreams_params = OutputVStreamParams.make_from_network_group(network_group, quantized=False)
        
        print("Hailo model loaded successfully")
        print(f"Input streams: {len(input_vstream_infos)}")
        print(f"Output streams: {len(output_vstream_infos)}")
        
        # Get model input shape
        input_shape = input_vstream_infos[0].shape
        model_height, model_width = input_shape[0], input_shape[1]
        print(f"Model input shape: {model_height}x{model_width}")
        
        hailo_device = target
        
    except Exception as e:
        print(f"Error initializing Hailo device: {e}")
        import traceback
        traceback.print_exc()
        print("Falling back to USB camera without inference")
        return run_camera_thread_usb(camera_index)
    
    while True:
        print(f"Opening USB camera at index {camera_index}...")
        
        # Open the camera using OpenCV
        cap = cv2.VideoCapture(camera_index)
        
        if not cap.isOpened():
            print(f"Error: Could not open camera at index {camera_index}")
            time.sleep(5)
            continue
        
        # Set camera properties
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 640)
        cap.set(cv2.CAP_PROP_FPS, TARGET_FPS)
        
        print(f"USB camera opened successfully")
        
        try:
            with InferVStreams(network_group, input_vstreams_params, output_vstreams_params) as infer_pipeline:
                input_vstreams = infer_pipeline.input_vstreams
                output_vstreams = infer_pipeline.output_vstreams
                
                print("Starting inference loop...")
                
                while True:
                    ret, frame = cap.read()
                    
                    if not ret:
                        print("Error: Failed to read frame from camera")
                        break
                    
                    # Preprocess frame for Hailo
                    preprocessed = preprocess_frame_for_hailo(frame, model_height, model_width)
                    
                    # Run inference
                    input_data = {input_vstreams[0].name: preprocessed}
                    
                    # Send to Hailo and get results
                    with network_group.activate(network_group_params):
                        infer_results = infer_pipeline.infer(input_data)
                    
                    # Post-process results and draw on frame
                    # Note: You'll need to implement proper postprocessing based on your model
                    output_data = list(infer_results.values())
                    frame_with_detections = postprocess_yolov8_hailo(output_data, frame)
                    
                    # Encode the frame as JPEG
                    ret, jpeg = cv2.imencode('.jpg', frame_with_detections)
                    
                    if not ret:
                        print("Error: Failed to encode frame as JPEG")
                        continue
                    
                    # Convert to bytes
                    frame_bytes = jpeg.tobytes()
                    
                    # Update the global frame
                    with global_frame_lock:
                        global_frame = frame_bytes
                    
                    # Control frame rate
                    time.sleep(FRAME_DURATION)
                    
        except Exception as e:
            print(f"Error while capturing/inferencing from USB camera: {e}")
            import traceback
            traceback.print_exc()
            
        finally:
            cap.release()
            print("USB camera released. Restarting...")
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
    # Check environment variables
    use_usb_camera = os.getenv('USB_CAMERA') == '1'
    use_hailo = os.getenv('USE_HAILO') == '1'
    hef_path = os.getenv('HAILO_MODEL_PATH', '/usr/share/hailo-models/yolov8s_h8l.hef')
    
    # Start the single camera thread in the background
    # Set it as a 'daemon' so it exits when the main app exits
    if use_usb_camera:
        if use_hailo:
            print("Using USB camera mode with Hailo inference")
            camera_thread = threading.Thread(
                target=run_camera_thread_usb_with_hailo,
                args=(0, hef_path)
            )
        else:
            print("Using USB camera mode without inference")
            camera_thread = threading.Thread(target=run_camera_thread_usb)
    else:
        print("Using rpicam mode")
        camera_thread = threading.Thread(target=run_camera_thread)
    
    camera_thread.daemon = True
    camera_thread.start()
    
    print("Starting Flask server on http://0.0.0.0:8080")
    # threaded=True is necessary to handle multiple clients
    app.run(host='0.0.0.0', port=8080, threaded=True)