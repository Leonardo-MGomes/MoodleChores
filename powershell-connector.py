from MoodleDownloader.MoodleDownloader import (
    MoodleAuth,
    MoodleCredentials,
    MoodleSession,
    MoodleDatabase,
    Scraper
    )
from sys import argv
from requests import Session


def arg_session_valid(*var):
    moodle_session = MoodleSession(login_cookies={"MoodleSession": var[0]})
    auth = MoodleAuth(Session(), moodle_session=moodle_session)
    return auth.is_session_valid()

def arg_login(*var):
    moodle_credentials = MoodleCredentials(var[0], var[1])
    moodle_auth = MoodleAuth(Session(), moodle_credentials=moodle_credentials)
    moodle_session = moodle_auth.login()
    return moodle_session.login_cookies["MoodleSession"]

actions = {
    "sessionvalid": arg_session_valid,
    "login": arg_login
}


if __name__ == "__main__":
    try:
        print(actions[argv[1]](*argv[2:]))
    except IndexError:
        print("You need an action and some parameters, below are the available actions.")
        print(list(actions.keys()))
    except KeyError:
        print("Action not valid, below are the available actions.")
        print(list(actions.keys()))
