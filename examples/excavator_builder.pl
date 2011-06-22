#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            (qw(max));
use Getopt::Long          (qw(GetOptions));
use Games::Lacuna::Client ();

  my $planet_name;

  GetOptions(
    'planet=s' => \$planet_name,
  );

  my $cfg_file = shift(@ARGV) || 'lacuna.yml';
  unless ( $cfg_file and -e $cfg_file ) {
    die "Did not provide a config file";
  }

  my $client = Games::Lacuna::Client->new(
                 cfg_file => $cfg_file,
                 # debug    => 1,
  );

# EDIT - Launch Planet(s)
  my @launch_planets = ("Plumeria", "Blue Jewel", "Green Expanse", "Twobal", "Reclaimation 1", "Reclaimation 2", "Reclaimation 3", "Reclaimation 4", "Reclaimation 5", "Ghost Reach");
  my $levelmin = 12;

# Load the planets
  my $empire  = $client->empire->get_status->{empire};
  my $planets = $empire->{planets};
  
  my $available_slots = 0;
  
  if($empire->{rpc_count} > 9800) {
  	print "High RPC Count ($empire->{rpc_count}). Exiting.\n";
  	exit 1;
  }

# Scan each planet
  foreach my $planet_id ( sort keys %$planets ) {
    my $name = $planets->{$planet_id};

    next if !(grep {$_ eq $name} @launch_planets);

    print "Checking Space Ports on $name:\n";

    # Load planet data
    my $planet    = $client->body( id => $planet_id );
    my $result    = $planet->get_buildings;
    my $body      = $result->{status}->{body};
    
    my $buildings = $result->{buildings};

    # Find the first Space Port
    my $space_port_id = List::Util::first {
            $buildings->{$_}->{name} eq 'Space Port'
    } keys %$buildings;
    
    next if !$space_port_id;
    
    my $space_port = $client->building( id => $space_port_id, type => 'SpacePort' );
    my $port_view = $space_port->view();
    
    $available_slots = $port_view->{docks_available};
	print "$available_slots docks open.\n";
	
	print "Getting Shipyards over L$levelmin";
	
	# Find the Shipyards
	my @yard_ids = grep {
			$buildings->{$_}->{name} eq 'Shipyard'
	}
	grep { $buildings->{$_}->{level} > $levelmin and $buildings->{$_}->{efficiency} == 100 }
	keys %$buildings;
    
    print " (@yard_ids):\n";
    
    #stream output
    $| = 1;
    
    my $ports = @yard_ids;
    
    my $tobuildcount = int(($available_slots - 1) / $ports);
    foreach my $yard (@yard_ids) {
    	my $thisyard = $client->building( id => $yard, type => 'Shipyard' );
    	my $yresp = $thisyard->view_build_queue();
    	
    	my $count = $tobuildcount - $yresp->{number_of_ships_building};
    	if($count < 0) { $count = 0; }
    	
    	print "Building $count at $thisyard: ";
    	
    	
    	while($count-- > 0) {
    			sleep 2;
			my $ok = eval {
				my $resp = $thisyard->build_ship("excavator");
				print $resp->{number_of_ships_building};
				print " ";
				return 1;
			};
			unless ($ok) {
				if (my $e = Exception::Class->caught('LacunaRPCException')) {
					if ($e->code eq '1013') {
						print "full\n";
						last;
					}
				}
				else {
					my $e = Exception::Class->caught();
					ref $e ? $e->rethrow : die $e;
				}
			}
    	

    	}
    	print "\n";
    }
 
    print "\n";
  }
  
exit;

sub _prettify_name {
    my $name = shift;
    
    $name = ucfirst $name;
    $name =~ s/_(\w)/" ".ucfirst($1)/ge;
    
    return $name;
}
