from fastapi import FastAPI

app = FastAPI(title="Smart Parking IoT Algorithm Engine")

@app.get("/")
def read_root():
    return {"status": "Operational", "module": "A* & Dijkstra Core"}

