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
from MoodleDownloader.MoodleDownloader.exceptions import (
    MoodleCourseNotFound
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
        if moodle_session.sesskey is None:
            moodle_session.sesskey = auth._extract_sesskey()
        return func(auth, *var[1:])
    return wrapper


@action("sessionvalid")
@authenticated
def arg_session_valid(auth):
    return auth.is_session_valid()


@action("get-course")
@authenticated
def arg_course(auth, course_id, update_db = True):
    scraper = Scraper(auth.session, auth)
    course = scraper.create_dataclass(int(course_id))
    if update_db:
        db = MoodleDatabase()
        db.add_course(course)
    return json.dumps(asdict(course), cls=MoodleJsonEncoder)


@action("login")
def arg_login(*var):
    moodle_credentials = MoodleCredentials(var[0], var[1])
    moodle_auth = MoodleAuth(Session(), moodle_credentials=moodle_credentials)
    moodle_session = moodle_auth.login()
    return moodle_session.login_cookies["MoodleSession"]


@action("db-courses")
def arg_db_courses(*var):
    db = MoodleDatabase()
    courses = db.from_database_to_object()
    return json.dumps([asdict(c) for c in courses], cls=MoodleJsonEncoder)


@action("db-index-course")
@authenticated
def arg_db_index_course(auth, course_id):
    scraper = Scraper(auth.session, auth)
    course = scraper.create_dataclass(int(course_id))
    MoodleDatabase().add_course(course)
    return json.dumps(asdict(course), cls=MoodleJsonEncoder)


@action("db-sync")
@authenticated
def arg_db_sync(auth):
    scraper = Scraper(auth.session, auth)
    db = MoodleDatabase()
    available_courses = scraper.get_available_courses()

    added_courses = []
    for course_info in available_courses:
        course_id = int(course_info['id'])
        if not db.check_database_for_course_id(course_id):
            try:
                course_obj = scraper.create_dataclass(course_id)
            except MoodleCourseNotFound:
                continue # Just ignore it for now
            except AttributeError:
                continue # I've got ABSOLUTELY no idea where this comes from, and I'm too tired to look at it. Probably from that one course with a topic that has a dependency (isn't that the powershell module aka this one?)

            db.add_course(course_obj)
            added_courses.append(asdict(course_obj))

    return json.dumps(added_courses, cls=MoodleJsonEncoder)

@action("db-check-course")
def arg_db_check_course(*var):
    return MoodleDatabase().check_database_for_course_id(int(var[0]))


if __name__ == "__main__":
    try:
        print(actions[argv[1]](*argv[2:]))
    except IndexError:
        print("You need an action and some parameters, below are the available actions.")
        print(list(actions.keys()))
    except KeyError:
        print("Action not valid, below are the available actions.")
        print(list(actions.keys()))
