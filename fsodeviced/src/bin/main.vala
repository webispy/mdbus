/**
 * Copyright (C) 2009 Michael 'Mickey' Lauer <mlauer@vanille-media.de>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.

 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.

 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA
 *
 */

GLib.MainLoop mainloop;
FsoFramework.Logger logger;

public static void sighandler( int signum )
{
    Posix.signal( signum, null ); // restore original sighandler
    logger.info( "received signal -%d, exiting.".printf( signum ) );
    mainloop.quit();
}

public static int main( string[] args )
{
    logger = FsoFramework.createLogger( "fsodevice" );
    logger.info( "fsodevice starting up..." );
    var subsystem = new FsoFramework.BaseSubsystem( "odevice" );
    subsystem.registerPlugins();
    uint count = subsystem.loadPlugins();
    logger.info( "loaded %u plugins".printf( count ) );
    mainloop = new GLib.MainLoop( null, false );
    logger.info( "fsodevice => mainloop" );
    Posix.signal( Posix.SIGINT, sighandler );
    Posix.signal( Posix.SIGTERM, sighandler );
    // enable for release version?
    //Posix.signal( Posix.SIGBUS, sighandler );
    //Posix.signal( Posix.SIGSEGV, sighandler );
    mainloop.run();
    logger.info( "mainloop => fsodevice" );
    logger.info( "fsodevice shutdown." );
    return 0;
}
