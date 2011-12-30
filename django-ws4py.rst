public: yes

=======================================
Django Websockets With Gevent and Ws4py
=======================================

I recently started researching websockets_ for a personal project. I have
a Django application that requires two-way real-time communication with
the web-server. Traditionally, the techniques to achieve this were streaming
and long-polling, commonly known under an umbrella term "Comet_". Having
built a working prototype of a STOMP Django-Comet application once before
using Twisted, Orbited and MorbidQ, I know how much time it takes to align
all the moving pieces there and wouldn't be looking forward to doing it all
over again. Luckily, the web evolves and all major browsers nowadays support
websockets natively and projects like web-socket-js_ exist to extend
websockets support to older browsers. Finally, there is Socket.IO_, which
takes the pain out of creating fall-back mechanisms for all the corner
cases.

First, I couldn't find a suitable websocket server code to be inserted into
Django and settled on a Tornado_\ -based websocket server deployed
alongside the Django application on the server, but quickly realized that
approach places too much logic on the side of this websocket server and
results in a lot of code duplication between that and the Django
application. Moreover, a separate API is needed on the side of the Django
application to communicate with the websocket server, which either adds
a lot of wrapper code or exposes too much of the internal API.  Furthermore,
there is a question of authentication of clients to the websocket server
and how this authentication information is relayed and processed within the
*django* |--| *browser* |--| *websocket server* triangle. This prodded
me to search for alternatives once again.

Finally, I came across gevent-websocket_ and gevent-socketio_ projects by 
Jeffrey Gilens and a comprehensive `tutorial series`__ by Cody Soyland on
integrating these with a Django application. Stephen McDonald took these
ideas and created a django-socketio_ package, which is supposed to make a
*gevent* |--| *websockets* |--| *socket.io* |--| *Django* stack extremely
easy to integrate into your code. The more I played around with these, the
more it seemed like that I needed all along |---| a way to handle
websockets from within the Django application itself.

I was drawn to Gevent_ by another aspect of it as well |---| no-effort
multi-tasking. With Tornado I spent a lot of time trying to integrate ready
libraries into its non-blocking mode of operation. Gevent_ seems to
monkey-patch all blocking operations with coroutine-friendly ones, making
existing code work without modifications.

.. __: http://codysoyland.com/2011/feb/6/evented-django-part-one-socketio-and-gevent/

Why ws4py?
==========

The web evolves! Sometimes it evolves way too fast for our liking. At the
time, websockets was not an RFC document, but a working group draft that
was evolving and changing fast. With it, the browser support of the draft
was evolving rapidly and a curious void appeared. Gevent-websocket_
supported the protocol up to *hybi-07* specification. *Hybi-10* support was
in the works. Firefox 6 supported *hybi-07*, but Chrome 14 already required
*hybi-10*. This would be all masked away by Socket.IO choosing a different
transport where the websocket negotiations failed, but Gevent-socketio_ was
experiencing problems with transports.

Furthermore, Gevent-socketio_ was stuck at Socket.IO version 0.6 while
Socket.IO_ website is advertising version 0.8 already and the sparseness of
documentation started to wear on me...

Finally, I found the ws4py_ project. I was attracted by support for
multiple web-servers and an integration of the `Autobahn test suite`_.
Multiple web-server support (ws4py can be integrated with Gevent and
Tornado alike) meant that I have the option to switch away from Gevent with
its cooperative multitasking paradigms if they become a problem later on. A
comprehensive test suite like Autobahn, which is the de facto standard test
suite for websocket implementations means that there should be no bugs and
ugly surprises along the way.

Integrating Gevent and Ws4py
============================

Even though ws4py has all the code needed to integrate with gevent, it
doesn't quite fit my idea of how it should do that. Denis Bilenko, the
creator of gevent seems to have `his own idea`__ as well. Unlike Denis, I
would like to rewrite as little of ws4py code as possible and reuse as much
of it as possible.

.. __: https://github.com/denik/WebSocket-for-Python/commit/92ae7aae49fbec76047fdcdb2b8cf91ad9c03f26

Turning a normal HTTP request into a websocket connection is triggered by a
``Upgrade: websocket`` header field in the request. The handling of a
websocket request in ws4py is done by the following classes: 
``ws4py.server.wsgi.middleware.WebSocketUpgradeMiddleware``,
``ws4py.server.geventserver.UpgradeWSGIHandler`` and
``ws4py.server.geventserver.WebSocketServer``.

The middleware class checks if the request environment contains a
``upgrade.protocol`` property set to ``websocket``. If it does, the
middleware performs a websocket server-side part of the handshare and,
if successful, responds with a "101 - Websocket Handshake" status and creates a
websocket object (a socket-like object to pass messages over the websocket
connection) that is given to a websocket handler application as
``app(websocket, environ)``. If the handshake fails (for reasons such as
unsupported protocol version, headers missing or no upgrade requested), the
middleware calls a fall-back application as ``app(environ, start_response)``.
If no fall-back application is given, "400 - Bad Handshake" status is
returned.

The ``UpgradeWSGIHandler`` class takes care of setting up the necessary
environment variables for the upgrade (such as ``upgrade.protocol``) and
releasing the socket handler if the application responds with a "101 -
Websocket Handshake" status. If no upgrade header fields are found, the
handler calls the application without any upgrade tracking.

The ``WebSocketServer`` WSGI server class ties the functionality described
above with a websocket handler application that is given to it.

The server class, in my opinion, is too simple to do enough work to be
useful. It will take a websocket handler application as input and wrap it
with the upgrade middleware. Nowhere can you set the fall-back application.
The consequences of these are that if the upgrade headers are present, the
middleware is called and the provided websocket handler application is
called. If the upgrade headers are not set, the middleware is called and a
"400 - Bad Handshake" error is returned.

I had a different idea for the WSGI server |---| I want the request be
always be routed to Django. If the upgrade headers are in place and the
websocket handshake is successful, I want a ``wsgi.websocket`` environment
variable to be set with that socket. We will add an
``extensions/adaptation.py`` file to out Django project and rewrite the
middleware as follows:

.. code-block:: python
::


    from ws4py.server.wsgi.middleware import \
         WebSocketUpgradeMiddleware as Ws4pyWebSocketUpgradeMiddleware

    class WebSocketMiddleware( Ws4pyWebsocketUpgradeMiddleware ):

        def __init__( self, handle, server, *args, **args ):

            self.app_handle = handle
            self.server = server

            super(WebSocketUpgradeMiddleware, self).__init__( self.websocket_handle,
                                                              *args, **kwargs )

        def websocket_handle( self, websocket, environ ):

            def null_start_reponse( status, data ): pass

            environ[ 'wsgi.websocket' ] = websocket
            environ[ 'wsgi.server' ] = self.server
            return self.app_handle( environ, null_start_response )

        def __call__( self, environ, start_reponse ):

            if 'websocket' not in environ.get( 'upgrade.protocol', '' ):
                return self.app_handle( environ, start_response )

            return super(WebSocketUpgradeMiddleware, self).__call__( environ,
                                                                     start_response )

Now, we need a WSGI server class that inserts the websocket middleware as
the first handler. This can be accomplished with this almost verbatim copy
of ``WebSocketServer``:

.. code-block:: python
::

    from gevent.pywsgi import WSGIServer
    from ws4py.server.geventserver import UpgradableWSGIHandler

    class WebSocketServer( WSGIServer ):
        
        handler_class = UpgradableWSGIHandler

        def __init__( self, *args, **kwargs ):
            super(WebSocketServer, self).__init__(*args, **kwargs)
            protocols = kwargs.pop( 'websocket_protocols', [] )
            extensions = kwargs.pop( 'websocket_extensions', [] )
            self.application = WebSocketUpgradeMiddleware( self.application,
                                                           server=self,
                                                           protocols=protocols,
                                                           extensions=extensions )

Gevent and Django
=================

First thing first |---| running with gevent, we need to monkey-patch the
standard library to make it compatible with the cooperative multitasking
nature of gevent. This is as easy as calling ``gevent.monkey.patch_all()``
function, but where to do it? The beginning of ``settings.py`` seems like a
suitable place for it, but ``settings.py`` is imported many times from
different parts of the code while ``patch_all()`` needs to be called
exactly once.

A little code of pythonic blasphemy comes to the recue:

.. code-block:: python
::

    def first_time( id ):
        import __builtin__
        id = '__first_time_' + id
        running_first_time = getattr( __builtin__, id, True )
        setattr( __builtin__, id, False )
        return running_first_time

Having this function makes it possible to have code like:

.. code-block:: python
::

    if first_time( 'foo' ):
        # do something foo-related only once
        ....

The inner code block of the if-clause will be executed exactly once, no
matter how many times the code that icludes this if-clause is imported from
other places. It works by polluting the built-in namespace with a variable
``__first_time_foo = False`` when ``first_time( 'foo' )`` is called the
first time. It works well since there can only ever be one built-in
namespace and ``import __builtin__`` will always return the same module
whenever it is called. Many python purists will say that you should not
litter the built-in namespace like that, but the code above works and works
well regardless of whether it is ultimately the right thing to do.

So, without further concerns, we create a ``gevent_specific.py`` file:


.. code-block:: python
::

    def first_time( id ):
        ...

    if first_time( 'gevent_specific' ):
        # Monkey-patch the standard libraries to make them greenlet-friently
        import gevent.monkey
        gevent.monkey.patch_all()

You may want to do more here. If you use a MySQL database, for example, you
can use pymysql instead of mysqldb, as `this discussion`__ suggests.

.. __: http://stackoverflow.com/questions/2636536/how-to-make-django-work-with-unsupported-mysql-drivers-such-as-gevent-mysql-or-c

Then, at the beginning of ``settings.py`` we'll simply add:

.. code-block:: python
::

    import gevent_specific

Running Django
==============

The next step is to create a server that will be based on the
``WebSocketServer`` above so that the requests will be processed
accordingly. The easiest way is to clone the ``runserver`` management
command that is used to run the Django development server. Django-socketio_
project, for example, does just that to substitute the default Django HTTP
server with a custom Socket.IO server, creating a new management command,
``runserver_socketio``.

Furthermore, I have been using django-extensions_\ ' ``runserver_plus``
command for a long time and I love the Werkzeug_ in-browser interactive
debugger and how it allows to inspect the exceptions in context by allowing
the developer to execute arbitrary code in the context of traceback frames
right from within the the browser.

We will create a ``extensions/management/commands/superserver.py`` with the
following content:




.. _websockets: http://websocket.org/
.. _web-socket-js: https://github.com/gimite/web-socket-js
.. _Tornado: http://www.tornadoweb.org/
.. _Comet: http://en.wikipedia.org/wiki/Comet_(programming)
.. _Socket.IO: http://socket.io
.. _Gevent: http://www.gevent.org/
.. _gevent-websocket: https://bitbucket.org/Jeffrey/gevent-websocket
.. _gevent-socketio: https://bitbucket.org/Jeffrey/gevent-socketio
.. _django-socketio: https://github.com/stephenmcd/django-socketio
.. _ws4py: https://github.com/Lawouach/WebSocket-for-Python
.. _autobahn test suite: http://www.tavendo.de/autobahn/testsuite.html

.. |--| unicode:: U+2013   .. en dash
.. |---| unicode:: U+2014  .. em dash, trimming surrounding whitespace
   :trim:


..
    vim: tw=75 wrap
