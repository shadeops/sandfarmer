import random
import time
from flask import Flask
from flask import request

app = Flask(__name__)

@app.route("/Tractor/monitor", methods = ['GET', 'POST'])
def hello_world():
    query = request.args.get('q')
    if query == "login":
        return {"tsid" : "0123456789012345678901234567890123456"}

    query = request.form.get('q')
    if query == "login":
        return {"tsid" : "0123456789012345678901234567890123456"}

    ret = {"mbox" : []}
    for i in range(random.randint(10,1000)):
        cmd = [
            "c",
            random.randint(1,100), # jid
            random.randint(0,100), # tid
            random.randint(0,5), # cid
            random.choice("ABDE"), # status
            1, # has log
            "localhost", # hostname
            "9005", # port
            random.randint(0,100), # numtasks
            random.randint(0,100), # numactive
            random.randint(0,100), # numdone
            random.randint(0,100), # numerror
            "jmp", # owner
            time.time(), # unix time
        ]
        ret["mbox"].append(cmd)
    return ret

