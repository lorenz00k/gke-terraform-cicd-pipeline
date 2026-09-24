from flask import Flask, jsonify
import random
import socket

app = Flask(__name__)

count = 0

@app.route('/', methods=['GET'])
def default():
    return jsonify({
        'message': "Hello from GKE!", 'pod': socket.gethostname() 
    })

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({
        'status': "ok",
    }), 200

@app.route('/random', methods=['GET'])
def random_check():
    # Simulating a database connection check
    db_status = "healthy" if random.choice([True, False]) else "unhealthy"

    # Simulating a cache check
    cache_status = "healthy" if random.choice([True, False]) else "unhealthy"

    overall_status = "healthy" if db_status == "healthy" and cache_status == "healthy" else "unhealthy"

    return jsonify({
        'status': overall_status,
        'database': db_status,
        'cache': cache_status
    }), 200

# will count only per pod instance; not over the whole cluster 
@app.route('/count', methods=['GET'])   
def counter():
    global count
    count += 1
    return jsonify({
        'Counted per pod:': count
    }), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
