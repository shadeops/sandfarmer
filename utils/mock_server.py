import os
import time
import random
from flask import Flask
from flask import request

app = Flask(__name__)

hosts = [ "blade%i"%i for i in range(10) ]
users = ["cat", "dog", "cow", "pig", "crow", "fish", "fly", os.environ.get("USER","")]
division = ["good", "evil", "neutral"]
dept = ["good", "evil", "neutral"]
sub = ["chaotic", "lawful", "neutral"]
unit = ["mages", "warriors", "rogues"]
#division
#dept.sub.unit

min_tasks = 1
max_tasks = 100

@app.route("/Tractor/monitor", methods = ["GET", "POST"])
def get_tasks():
    query = request.form.get("q")
    if query == "login":
        return {"tsid" : "0123456789012345678901234567890123456"}

    min_arg = int(request.args.get("min", 1))
    max_arg = int(request.args.get("max", 100))

    ret = {"mbox" : []}
    for i in range(random.randint(min_arg,max_arg)):
        cmd = [
            "c",
            random.randint(1,100), # jid
            random.randint(0,100), # tid
            random.randint(0,5), # cid
            random.choices("ABDE", weights=[1, 0.05, 1, 0.2], k=1 )[0], # status
            1, # has log
            random.choice(hosts), # hostname
            "9005", # port
            random.randint(0,100), # numtasks
            random.randint(0,100), # numactive
            random.randint(0,100), # numdone
            random.randint(0,100), # numerror
            random.choice(users), # owner
            time.time(), # unix time
        ]
        ret["mbox"].append(cmd)
    return ret

@app.route("/Tractor/config", methods = ["GET"])
def get_blades():
    query_arg = request.args.get("q")
    file_arg = request.args.get("file")
    if query_arg == "get" and file_arg == "blade.config":
        ret = {"BladeProfiles" : []}
        profile = {
            "ProfileName" : "profile_1",
            "Hosts" : {
                "Name" : hosts[0:4]
            }
        }
        ret["BladeProfiles"].append(profile)
        profile = {
            "ProfileName" : "profile_2",
            "Hosts" : {
                "Name" : hosts[4:9]
            }
        }
        ret["BladeProfiles"].append(profile)
        profile = {
            "ProfileName" : "profile_3",
            "Hosts" : {
                "Name" : hosts[9:]
            }
        }
        ret["BladeProfiles"].append(profile)
        return ret

    return "wut?"

@app.route("/whoswho", methods = ["GET"])
def whoswho():
    ret = {}
    for i,user in enumerate(users):
        entry = {
            "login" : user,
            "division" : random.choice(division),
            "dept" : random.choice(dept),
            "sub" : random.choice(sub),
            "unit" : random.choice(unit),
        }
        ret[str(i)] = entry
    return ret

