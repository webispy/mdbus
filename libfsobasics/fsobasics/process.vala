/*
 * Copyright (C) 2009-2010 Michael 'Mickey' Lauer <mlauer@vanille-media.de>
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

/**
 * @interface FsoFramework.IProcessGuard
 **/
public interface FsoFramework.IProcessGuard : GLib.Object
{
    public abstract bool launch( string[] command );
    public abstract void stop( int sig = Posix.SIGTERM );
    public abstract void setAutoRelaunch( bool on );

    public abstract bool sendSignal( int sig );
    public abstract bool isRunning();

    public signal void running();
    public signal void stopped();
}

/**
 * @class FsoFramework.GProcessGuard
 **/
public class FsoFramework.GProcessGuard : FsoFramework.IProcessGuard, GLib.Object
{
    private Pid pid;
    private uint watch;
    private string[] command;
    private bool relaunch;

    public Posix.pid_t _pid()
    {
        return (Posix.pid_t)pid;
    }

    ~GProcessGuard()
    {
        if ( pid != (Pid)0 )
        {
#if DEBUG
            warning( "Guard being freed, while child %d still running. This is most likely a bug in your problem. Trying to kill the child in a synchronous way...", (int)pid );
#endif
            relaunch = false;
            syncStop();
        }
    }

    public bool launch( string[] command )
    {
        this.command = command; // save for possible relaunching

        if ( pid != (Pid)0 )
        {
            warning( @"Can't launch $(command[0]); already running as pid %d".printf( (int)pid ) );
            return false;
        }

        try
        {
            GLib.Process.spawn_async( GLib.Environment.get_variable( "PWD" ),
                                      command,
                                      null,
                                      GLib.SpawnFlags.DO_NOT_REAP_CHILD | GLib.SpawnFlags.SEARCH_PATH,
                                      null,
                                      out pid );
        }
        catch ( SpawnError e )
        {
            warning( @"Can't spawn $(command[0]): $(strerror(errno))" );
            return false;
        }

        watch = GLib.ChildWatch.add( pid, onChildWatchEvent );
        this.running(); // SIGNAL
        return true;
    }

    public bool launchWithPipes( string[] command, out int fdin, out int fdout )
    {
        this.command = command; // save for possible relaunching

        if ( pid != (Pid)0 )
        {
            warning( @"Can't launch $(command[0]); already running as pid %d".printf( (int)pid ) );
            return false;
        }

        try
        {
            GLib.Process.spawn_async_with_pipes(
                GLib.Environment.get_variable( "PWD" ),
                command,
                null,
                GLib.SpawnFlags.DO_NOT_REAP_CHILD | GLib.SpawnFlags.SEARCH_PATH,
                null,
                out pid,
                out fdin,
                out fdout,
                null );
        }
        catch ( SpawnError e )
        {
            warning( @"Can't spawn w/ pipes $(command[0]): $(e.message))" );
            return false;
        }

        watch = GLib.ChildWatch.add( pid, onChildWatchEvent );
        this.running(); // SIGNAL
        return true;
    }

    // FIXME: consider making this async?
    public void stop( int sig = Posix.SIGTERM )
    {
        stopSendStopped( true );
    }

    public void setAutoRelaunch( bool on )
    {
        relaunch = on;
    }

    public bool sendSignal( int sig )
    {
        if ( pid == (Pid)0 )
        {
            return false;
        }

        var res = Posix.kill( (Posix.pid_t)pid, sig );
        return res == 0;
    }

    public bool isRunning()
    {
        return ( pid != (Pid)0 );
    }

    //
    // private API
    //
    private void stopSendStopped( bool send )
    {
        _stop( send );
    }

    private void cleanupResources()
    {
        if ( watch > 0 )
        {
            GLib.Source.remove( watch );
        }
        GLib.Process.close_pid( pid );
        pid = 0;
        this.stopped();
    }

    private void onChildWatchEvent( Pid pid, int status )
    {
        if ( this.pid != pid )
        {
            critical( "D'OH!" );
            return;
        }
#if DEBUG
        debug( "CHILD WATCH EVENT FOR %d: %d", (int)pid, status );
#endif
        pid = 0;
        cleanupResources();

        if ( relaunch )
        {
#if DEBUG
            debug( "Relanching requested..." );
#endif
            if ( ! launch( command ) )
            {
                warning( @"Could not relaunch $(command[0]); disabling." );
                relaunch = false;
            }
        }
    }

    internal const int KILL_SLEEP_TIMEOUT  = 1000 * 1000 * 5; // 5 seconds
    internal const int KILL_SLEEP_INTERVAL = 1000 * 1000 * 1; // 1 second

    private async void _stop( bool send )
    {
        if ( (Posix.pid_t)pid == 0 )
        {
            return;
        }
#if DEBUG
        debug( "Attempting to stop pid %d - sending SIGTERM first...", pid );
#endif
        Posix.kill( (Posix.pid_t)pid, Posix.SIGTERM );
        var done = false;
        var timer = new GLib.Timer();
        timer.start();

        while ( !done && pid != 0 )
        {
            var pid_result = Posix.waitpid( (Posix.pid_t)pid, null, Posix.WNOHANG );
#if DEBUG
            debug( "Waitpid result %d", pid_result );
#endif
			if ( pid_result < 0 )
			{
				done = true;
#if DEBUG
				debug( "Failed to wait for process to exit: waitpid returned %d", pid_result );
#endif
			}
			else if ( pid_result == 0 )
			{
				if ( timer.elapsed() >= KILL_SLEEP_TIMEOUT )
				{
#if DEBUG
					debug( "Timeout for pid %d elapsed, exiting wait loop", pid );
#endif
					done = true;
				}
				else
				{
#if DEBUG
					debug( "Process %d is still running, waiting...", pid );
#endif
                    Timeout.add_seconds( 1, _stop.callback );
                    yield;
				}
			}
			else /* pid_result > 0 */
			{
				done = true;
#if DEBUG
				debug( "Process %d terminated normally", pid );
#endif
				GLib.Process.close_pid( pid );
				pid = 0;
			}
        }

        if ( pid != 0 )
        {
            warning( "Process %d ignored SIGTERM, sending SIGKILL", pid );

            if ( watch > 0 )
            {
                GLib.Source.remove( watch );
                watch = 0;
            }

            Posix.kill( (Posix.pid_t)pid, Posix.SIGKILL );
            Thread.usleep( 1000 );
            pid = 0;
#if DEBUG
            debug( "Process %d stop complete", pid );
#endif
        }

        if ( send )
        {
            this.stopped();
        }
    }

    private void syncStop()
    {
        if ( watch > 0 )
        {
            GLib.Source.remove( watch );
            watch = 0;
        }
#if DEBUG
        debug( "Attempting to syncstop pid %d - sending SIGTERM first...", pid );
#endif
        Posix.kill( (Posix.pid_t)pid, Posix.SIGTERM );
        var done = false;
        var timer = new GLib.Timer();
        timer.start();

        while ( !done && pid != 0 )
        {
            var pid_result = Posix.waitpid( (Posix.pid_t)pid, null, Posix.WNOHANG );
#if DEBUG
            debug( "Waitpid result %d", pid_result );
#endif
			if ( pid_result < 0 )
			{
				done = true;
#if DEBUG
				debug( "Failed to syncwait for process to exit: waitpid returned %d", pid_result );
#endif
			}
			else if ( pid_result == 0 )
			{
				if ( timer.elapsed() >= KILL_SLEEP_TIMEOUT )
				{
#if DEBUG
					debug( "Timeout for pid %d elapsed, exiting syncwait loop", pid );
#endif
					done = true;
				}
				else
				{
#if DEBUG
					debug( "Process %d is still running, sync waiting...", pid );
#endif
                    Thread.usleep( KILL_SLEEP_INTERVAL );
				}
			}
			else /* pid_result > 0 */
			{
				done = true;
#if DEBUG
				debug( "Process %d terminated normally", pid );
#endif
				GLib.Process.close_pid( pid );
				pid = 0;
			}
        }

        if ( pid != 0 )
        {
            warning( "Process %d ignored SIGTERM, sending SIGKILL", pid );

            if ( watch > 0 )
            {
                GLib.Source.remove( watch );
            }

            Posix.kill( (Posix.pid_t)pid, Posix.SIGKILL );
            Thread.usleep( 1000 );
            pid = 0;
#if DEBUG
            debug( "Process %d stop complete", pid );
#endif
        }
    }
}