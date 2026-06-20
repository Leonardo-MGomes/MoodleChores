import enum
import json
from dataclasses import asdict
from functools import wraps
from sys import argv
from requests import Session

from MoodleDownloader.MoodleDownloader import (
    MoodleAuth,
    MoodleCredentials,
    MoodleSession,
    MoodleDatabase,
    Scraper
)


class MoodleJsonEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, enum.Enum):
            return obj.value
        return super().default(obj)

actions = {}


def action(name):
    def decorator(func):
        actions[name] = func
        return func
    return decorator


def authenticated(func):
    @wraps(func)
    def wrapper(*var):
        moodle_session = MoodleSession(login_cookies={"MoodleSession": var[0]})
        auth = MoodleAuth(Session(), moodle_session=moodle_session)
        return func(auth, *var[1:])
    return wrapper


@action("sessionvalid")
@authenticated
def arg_session_valid(auth):
    return auth.is_session_valid()


@action("get-course")
@authenticated
def arg_course(auth, course_id):
    scraper = Scraper(auth.session, auth)
    course = scraper.create_dataclass(int(course_id))
    return json.dumps(asdict(course), cls=MoodleJsonEncoder)


@action("login")
def arg_login(*var):
    moodle_credentials = MoodleCredentials(var[0], var[1])
    moodle_auth = MoodleAuth(Session(), moodle_credentials=moodle_credentials)
    moodle_session = moodle_auth.login()
    return moodle_session.login_cookies["MoodleSession"]


if __name__ == "__main__":
    try:
        print(actions[argv[1]](*argv[2:]))
    except IndexError:
        print("You need an action and some parameters, below are the available actions.")
        print(list(actions.keys()))
    except KeyError:
        print("Action not valid, below are the available actions.")
        print(list(actions.keys()))
