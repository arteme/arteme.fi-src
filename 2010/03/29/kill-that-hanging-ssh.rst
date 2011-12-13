public: yes
tags: [ ssh, xterm, hanging ]
summary: |
  I spend a lot of time working remotely, ``ssh``-ing to hosts from places
  with bad wireless connection or glitchy firewalls. In these circumstances
  ``ssh`` tends to get stuck a lot. Here is a painless way of killing these
  suck ``ssh`` processes.

======================
Kill That Hanging SSH!
======================

  **EDIT:** The script below was last updated on 2011-10-03 to simplify
  the window id extraction and various regexps. Now the script works in
  ``rxvt`` too.

I spend a lot of time working remotely, ``ssh``-ing to hosts from places
with bad wireless connection or glitchy firewalls. When an ``ssh`` session
hangs, it is bad enough. Trying to locate one dead ``ssh`` amid a dozen
live ones is tedious. It grows into a major headache if you need to do
that several times a hour. So, I have a dead ``ssh`` in an ``xterm``
window, how do I kill it? Moreover, how do I automate the process?

Luckily, most applications nowadays export the process id, controlling a
particular X window, as a property of that window and xprop_ is a tool
that can help us query that.

Run xprop_ as follows and click on the window of interest::

  arteme@book:~$ xprop _NET_WM_PID
  _NET_WM_PID(CARDINAL) = 17843

Knowing the process id of the terminal we can track down the ``ssh`` process
that runs within::

  arteme@book:~$ pstree -Ap 17843
  xterm(17843)---bash(17889)---ssh(21687)

There's a process id that can be killed.

Half the work is done and it seems that it can be easily rolled into a shell
script, but if you did, you would notice that if you started an xterm within
an xterm and an ssh within that, pstree output would look like::

  arteme@book:~$ pstree -Alp 3443
  xterm(3443)---bash(3447)---xterm(3705)---bash(3706)---ssh(9612)

If you start the second xterm in background and start ssh in both of them,
the output becomes even more chaotic::

  arteme@book:~$ pstree -Alp 3444
  xterm(3444)---bash(3446)-+-ssh(12549)
                           `-xterm(12508)---bash(12509)---ssh(12540)

So, what to kill?

Luckily, you can trace the ``ssh`` process back to the terminal window it is
running in by it's window id. Using xprop_ we can find out the window id
of the terminal, which is passed in the ``WINDOWID`` variable to the
processes started within. So, for the two ``xterm``\ s above with their
``ssh``::

  arteme@book:~$ xprop -f WM_CLIENT_LEADER '32c' ' = $0\n' WM_CLIENT_LEADER
  WM_CLIENT_LEADER(WINDOW) = 79691810
  arteme@book:~$ cat /proc/12549/environ | tr '\0' '\n' | grep WINDOWID
  WINDOWID=79691810

and::

  arteme@book:~$ xprop -f WM_CLIENT_LEADER '32c' ' = $0\n' WM_CLIENT_LEADER
  WM_CLIENT_LEADER(WINDOW) = 77594658
  arteme@book:~$ cat /proc/12540/environ | tr '\0' '\n' | grep WINDOWID
  WINDOWID=77594658

*By default, "xprop" will return the window id as in hex, so the "-f ..."
argument is necessary to override that and ease the comparison, since the
"WINDOWID" environment variable is in decimal.*

The bad news is that the ``WM_CLIENT_LEADER`` property is not set by all
terminal applications. ``Rxvt`` and its derivative ``urxvt`` are notoriusly
X-session-management-unaware and one would not find a ``WM_CLIENT_LEADER``
property there. The good news is that for a real script we do not need the
client leader property. We're only interested in identifying the active
selected window and xwininfo_ will give us an id of that...

Note, however, that if you run ``screen`` with multiple ssh instances within,
the environment of those ``ssh`` processes contains the ``WINDOWID`` of the
original xterm they were started in, if any. That information is not reliable
as it if you detached from the screen in one ``xterm`` and attached to it in
another one, the ``WINDOWID`` will no longer be correct. Luckily, one can
identify a screen session by the presence of the ``STY`` variable in the
environment...

Now this all can be rolled into a shell script:

.. code-block:: bash

  #!/bin/bash
  
  # Get the window id of the window the user clicked on
  wid=`xwininfo -int | sed -n 's/.*Window id: \([0-9]*\).*/\1/p'`
  
  # Get the process id from the window
  pid=`xprop -id $wid _NET_WM_PID | sed 's/.*= //'`
  
  # Exit if any of the data was missing
  [ -z "$wid" -o -z "$pid" ] && exit
  
  # Get the process tree and extract the ssh process id from there
  ssh=`pstree -Apl $pid | sed -n 's/.*ssh(\([0-9]\+\))/\1/p'`
  
  # Filter ssh windows so that they do not belong to a screen session and
  # do run in the X terminal the user clicked on
  for i in $ssh; do
      sty=`cat /proc/$i/environ | tr '\0' '\n' | grep '^STY'`
      window=`cat /proc/$i/environ | tr '\0' '\n' |\
              sed -n 's/WINDOWID=\(.*\)/\1/p'`
  
      [ -n "$sty" ] && continue
      [ "$wid" != "$window" ] && continue
  
      tokill="$tokill $i"
  done
  
  # Exit if there's nothing to kill
  [ -z "$tokill" ] && exit
  
  # Kill the process
  kill -9 $tokill

.. _xprop: http://www.xfree86.org/current/xprop.1.html
.. _xwininfo: http://www.xfree86.org/current/xwininfo.1.html


