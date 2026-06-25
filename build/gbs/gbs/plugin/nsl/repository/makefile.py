from typing import Optional, Tuple, List, Iterator
from pathlib import Path
import re

class MakefileError(Exception):
    """A malformed or unsupported construct in a Makefile.

    Carries the offending file so the failure is actionable, unlike the bare
    internal objects the evaluator used to leak (e.g. an orphan Else).
    """
    pass

class _UnbalancedConditional(Exception):
    """Internal: a structural conditional error raised while consuming the
    statement stream. Makefile.interpret annotates it with the file name and
    re-raises it as a MakefileError; it is never seen by callers."""
    pass

def balanced_paren(n: int) -> str:
    return r"[^()]*?(?:\("*n+r"[^()]*?"+r"\)[^()]*?)*?"*n

def nested_eval(max_depth: int) -> str:
    assert max_depth
    maybe_data = r"[^()]*?"
    data = r"[^()]+"
    eval_open = r"\$\("
    eval_close = r"\)"
    eval_ = eval_open + balanced_paren(max_depth - 1) + eval_close
    return r"(?:" + eval_ + r"|" + data + r")"

def nested_value(max_depth: int) -> str:
    maybe_data = r"[^()]*?"
    data = r"[^()]+"
    if max_depth:
        return maybe_data + r"(?:" + nested_eval(max_depth) + maybe_data + r")*?"
    return data

def nested_arg(max_depth: int) -> str:
    maybe_data = r"[^(),]*?"
    data = r"[^(),]+"
    if max_depth:
        return maybe_data + r"(?:" + nested_eval(max_depth) + maybe_data + r")*?"
    return data

class Statement:
    pass

class Assignment(Statement):
    """
    An assignment statement
    """
    def __init__(self, var: str, mode: str, value: str):
        """
        var: destination name
        mode: assignation mode
        value: value
        """
        self.var = var
        self.mode = mode
        self.value = value

    def evaluate(self, context: "Context") -> None:
        """
        Perform assignment in context

        var and value are both expanded with Make variable expansion
        rules at evaluation of assignment.
        """
        var = context.expand(self.var)

        if self.mode == "?=" and var in context:
            return

        if self.mode == ":=":
            value = context.expand(self.value)
        else:
            value = self.value

        if self.mode == "+=":
            value = context.get(var, "") + " " + value

        context[var] = value

class Warning(Statement):
    """
    A warning statement
    """
    def __init__(self, message: str):
        self.message = message

    def evaluate(self, context):
        pass
        #print(f"Makefile warning: {self.message}")
        
class Condition(Statement):
    """
    A condition (ifeq/ifneq)
    ifeq(a, b)
    """
    def __init__(self, mode: str, test: str):
        """
        ifeq(a, b)

        -> mode: 'ifeq'
        -> test: 'a, b'
        """
        self.mode = mode
        self.test = test

    def evaluate(self, context : "Context") -> bool:
        """
        Evaluate condition through context
        """
        if self.mode == "ifeq":
            a, b = self.ab_split(self.test)
            a = context.expand(a)
            b = context.expand(b)
            return a.strip() == b.strip()
        if self.mode == "ifneq":
            a, b = self.ab_split(self.test)
            a = context.expand(a)
            b = context.expand(b)
            return a.strip() != b.strip()
        raise NotImplementedError(self.mode)
    
    @classmethod
    def ab_split(cls, ab: str) -> Tuple[str, str]:
        args = Reader.arg_split(ab)
        return args[0], args[1]
    
class Else(Statement):
    pass

class EndIf(Statement):
    pass
        
class Reader:
    """
    Regex based parser for a Makefile

    Only support a subset of the actual syntax.
    """
    
    assignment = re.compile(r"^(?P<var>" + balanced_paren(5) + r")\s*(?P<mode>[:+?]?=)\s*(?P<value>.*)$", re.I)
    cond_ifeq = re.compile(r"^(?P<mode>ifn?eq)\s*\((?P<test>.*)\)\s*$")
    cond_else = re.compile(r"^(?P<cond>else)\s*$")
    cond_end = re.compile(r"^(?P<cond>endif)\s*$")
    warning = re.compile(r"^\$\(warning (?P<message>.*)\)\s*$")

    @classmethod
    def arg_split(cls, string: str) -> List[str]:
        arg_re = re.compile('^' + nested_value(5) + "$")
        no_commas = string.split(',')
        args = []
        cur = []
        for nc in no_commas:
            cur.append(nc)
            part = ','.join(cur)
            if arg_re.match(part):
                args.append(part)
                cur = []
        if cur:
            part = ','.join(cur)
            args.append(part)
        return args
    
    def __init__(self, path: Path):
        self.path = path

    def __iter__(self) -> Iterator[Statement]:
        fd = self.path.open("r")
        else_if = False
        for line in fd.readlines():
            line = line.rstrip().split("#", 1)[0]

            if not line:
                continue

            if line.startswith("else "):
                if else_if:
                    yield EndIf()
                    else_if = False
                yield Else()
                else_if = True
                line = line[5:].lstrip()
            
            if m := self.warning.match(line):
                r = Warning(m.group("message"))
            elif m := self.assignment.match(line):
                r = Assignment(m.group("var"), m.group("mode"), m.group("value"))
            elif m := self.cond_ifeq.match(line):
                r = Condition(m.group("mode"), m.group("test"))
            elif m := self.cond_else.match(line):
                r = Else()
            elif m := self.cond_end.match(line):
                if else_if:
                    yield EndIf()
                    else_if = False
                r = EndIf()
            else:
                # A conditional directive we couldn't parse (e.g. "if eq(...)",
                # "elif ...", "ifdef ...") would otherwise be silently dropped,
                # leaving its else/endif orphaned and crashing the evaluator on
                # an opaque internal object. Reject it here, where we still have
                # the offending line.
                token = line.split(None, 1)[0] if line.split() else ""
                if token in ("if", "ifeq", "ifneq", "ifdef", "ifndef", "elif"):
                    raise MakefileError(
                        f"{self.path}: unsupported conditional syntax: {line.strip()!r}"
                    )
                print(f"Unhandled line in makefile: {line}")
                continue
            yield r

class Context(dict):
    """
    An evaluation context (a set of variables defined to some values.
    Serves both as initial value for variables and as recipient for assignations.
    """
    def __init__(self, *args, **kwargs):
        dict.__init__(self)
        self.update(dict(*args, **kwargs))

    def evaluate(self, expression: str, exprs: Iterator["Statement"],
                 do_run: bool = True, prefix: str = ""):
        """
        Evaluate make expression (variable expansions, function calls)
        """
        #print(prefix, expression)
        if isinstance(expression, Condition):
            is_true = expression.evaluate(self)
            # Consume this conditional's body from the shared iterator: the
            # true branch up to an Else/EndIf, then the false branch up to the
            # EndIf. A nested Condition recurses and consumes its own EndIf, so
            # the next EndIf we see is always ours.
            in_true_branch = True
            while True:
                try:
                    te = next(exprs)
                except StopIteration:
                    raise _UnbalancedConditional(
                        f"unterminated '{expression.mode}' (missing 'endif')"
                    )
                if isinstance(te, EndIf):
                    return
                if isinstance(te, Else):
                    in_true_branch = False
                    continue
                branch_active = is_true if in_true_branch else not is_true
                self.evaluate(te, exprs, do_run = do_run and branch_active,
                              prefix = prefix + " ")

        if isinstance(expression, (Else, EndIf)):
            keyword = "else" if isinstance(expression, Else) else "endif"
            raise _UnbalancedConditional(
                f"'{keyword}' without matching 'ifeq'/'ifneq'"
            )

        if isinstance(expression, Assignment):
            if do_run:
                expression.evaluate(self)
            return

        if isinstance(expression, Warning):
            if do_run:
                expression.evaluate(self)
            return

        raise _UnbalancedConditional(f"unexpected statement: {expression!r}")

    dereference = re.compile(r"\$(?P<to_expand>\("+ balanced_paren(5)+r"\)|[^(])", re.I)

    def expanded_items(self):
        return {k: self.expand(v).strip() for (k, v) in self.items()}
    
    def expand(self, value: str) -> str:
        """
        Perform variable expansion
        """
        #print(f"Expand {value}", end = "")
        while True:
            before = value
            value = self.dereference.sub(self._dollar, value)
            if before == value:
                #print(f" -> {before} ({self})")
                return before

    def _dollar(self, m: str) -> str:
        """
        expand $(...)

        - Can be a function: $(function arg1,arg2,arg3)
        - Can be a variable: $(var)
        """
        exp = m.group("to_expand")
        #print(f"$<{exp}>")
        if exp.startswith('('):
            if ' ' in exp:
                function, args = exp[1:-1].split(' ', 1)
                args = Reader.arg_split(args)
                handler = getattr(self,
                                  "_func_"+function.replace("-", "_"),
                                  self._func__default)
                return handler(function, *args)
            exp = self.expand(exp[1:-1])
        else:
            exp = self.expand(exp)
        return self.get(exp)

    def _func__default(self, function : str, *args) -> str:
        raise NotImplementedError(f"Function {function} not implemented")
    
    def _func_filter(self, function: str, pattern: str, text: str) -> str:
        """
        $(filter pattern,text)
        """
        pattern = self.expand(pattern)
        text = self.expand(text)

        expected_result = function == "filter"
        
        pattern = re.escape(pattern).replace("%", ".*")
        p = re.compile("^" + pattern + "$")
        r = []

        for item in text.split():
            item = item.strip()
            if bool(p.match(item)) == expected_result:
                r.append(item)
        return ' '.join(r)

    _func_filter_out = _func_filter

    def _func_wildcard(self, function : str, path: str) -> str:
        """
        $(wildcard pattern)
        """
        path = self.expand(path)
        if path.startswith("/"):
            paths = Path("/").glob("." + path)
        else:
            paths = Path(".").glob(path)
        return ' '.join([str(x) for x in paths])

    def _func_if(self, function: str, cond: str, true: str, false: str) -> str:
        """
        $(if cond, if_true, if_false)
        """
        if self.expand(cond):
            return self.expand(true)
        else:
            return self.expand(false)
        return ' '.join([str(x) for x in paths])

    def _func_subst(self, function: str, f: str, t: str, text: str) -> str:
        """
        $(subst from, to, text)
        """
        f = self.expand(f)
        t = self.expand(t)
        return self.expand(text).replace(f, t)

class Makefile:
    """
    A makefile interpreter
    """
    filename: Path
    expressions: list[Statement]

    def __init__(self, filename: Path):
        self.filename = filename
        self.expressions = list(Reader(filename))

    def interpret(self, context: "Context"):
        exprs = iter(self.expressions)
        try:
            while True:
                try:
                    e = next(exprs)
                except StopIteration:
                    break
                context.evaluate(e, exprs)
        except _UnbalancedConditional as exc:
            raise MakefileError(f"{self.filename}: {exc}") from None

if __name__ == "__main__":
    import sys
    import click

    @click.command()
    @click.argument("makefiles", type = click.Path(dir_okay = False, file_okay = True, exists = True), nargs = -1)
    @click.option("-s", "--set", "settings", type = str, multiple = True)
    def dump(makefiles, settings):
        c = Context(dict([v.split('=',1) for v in settings]))

        for filename in makefiles:
            m = Makefile(Path(filename))
            m.interpret(c)

        for key, value in c.expanded_items():
            print(f"{key} = {value}")

    dump()
