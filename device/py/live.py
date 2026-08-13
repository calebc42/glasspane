"""live.py --- Jetpacs on-device pylsp fixture.

Mirrors test/smoke-eglot-lsp.el's JS fixture (the "alpha needle"
docstring pattern) for the Termux pylsp smoke: one documented member
(`alpha`) and one undocumented one (`beta`), with a trailing instance
reference so a dot lands right after it -- the completion AND
doc-hover trigger site in one, the way `smoke-lsp--seed' ends its JS
fixture with a bare "answer.".
"""


class Answer:
    """Fixture class for the eglot/pylsp completion + doc smoke."""

    def alpha(self):
        """The alpha needle documentation."""
        return 1

    def beta(self):
        return 2


a = Answer()
# GUARD: no trailing newline past this point. The on-device smoke
# seeds `edit.open' with this file's exact byte length as the cursor
# (see `smoke-lsp--seed' in test/smoke-eglot-lsp.el for the pattern
# this fixture mirrors), so EOF must land immediately after the "a."
# below -- one more byte and the completion/doc request lands on a
# blank line instead of on the member access. If a save-hook or
# `require-final-newline' adds one back before this reaches the
# device, strip it again:
#   printf '%s' "$(cat device/py/live.py)" > device/py/live.py
a.