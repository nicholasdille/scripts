#!/bin/bash

function stdin_is_terminal() {
    test -t 0
}

function stdout_is_terminal() {
    test -t 1
}

function stderr_is_terminal() {
    test -t 2
}

function stdin_is_a_pipe() {
    test -p /dev/stdin
}

function stdout_is_a_pipe() {
    test -p /dev/stdout
}

function stderr_is_a_pipe() {
    test -p /dev/stderr
}

function stdout_is_redirected() {
    ! stdout_is_a_pipe
}

function stderr_is_redirected() {
    ! stderr_is_a_pipe
}