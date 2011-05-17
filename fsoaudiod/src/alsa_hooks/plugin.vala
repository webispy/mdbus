/*
 * Copyright (C) 2011 Simon Busch <morphis@gravedo.de>
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

using GLib;

[DBus (name = "org.freesmartphone.Audio.Manager")]
interface AudioManager : Object {
    public abstract string register_session( string name ) throws IOError;
    public abstract void release_session( string token ) throws IOError;
}

AudioManager manager = null;
string active_token;
bool registered;

static const string FSOAUDIO_BUSNAME = "org.freesmartphone.oaudiod";
static const string FSOAUDIO_PATH = "/org/freesmartphone/Audio";
static const string FSOAUDIO_MANAGER_IFNAME = "org.freesmartphone.Audio.Manager";

static const int timeout = 10;

public int fsoaudio_request_session()
{
    registered = false;
    active_token = "";

    try
    {
        manager = Bus.get_proxy_sync( BusType.SYSTEM, FSOAUDIO_BUSNAME, FSOAUDIO_PATH );

        // FIXME currently we default to media stream type. We should choose the right
        // stream according to the device the user wants to open
        active_token = manager.register_session( "media" );
        registered = true;
    }
    catch ( Error err )
    {
    }

    return registered ? 0 : -1;
}

public int fsoaudio_release_session()
{
    if ( registered && manager != null && active_token.length > 0 )
    {
        try
        {
            manager.release_session( active_token );
            registered = false;
        }
        catch ( Error err )
        {
        }
    }

    return 0;
}

// vim:ts=4:sw=4:expandtab
