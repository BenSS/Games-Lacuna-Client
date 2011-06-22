#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            (qw(max));
use Getopt::Long          (qw(GetOptions));
use Games::Lacuna::Client ();

use DBI;
my $db = DBI->connect("dbi:SQLite:../stardist.db", "", "",
{RaiseError => 1, AutoCommit => 1});

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
  my @launch_planets = ("Plumeria", "Blue Jewel", "Reclaimation 1", "Reclaimation 2", "Reclaimation 3", "Reclaimation 4", "Reclaimation 5", "Green Expanse", "Twobal", "Ghost Reach");
  my $min_distance = 280;

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
    
    #stream output
    $| = 1;
    
    my $ships;
	my $ok = eval {
		$ships = $space_port->get_ships_for($planet_id, {body_name => "Blue Jewel"});
		return 1;
	};
	unless ($ok) {
		if (my $e = Exception::Class->caught('LacunaRPCException')) {
			if ($e->code eq '1002') {
				print "Empty Orbit\n";
			}
		}
		else {
			my $e = Exception::Class->caught();
			ref $e ? $e->rethrow : die $e;
		}
	}
	
	my $avail = $ships->{available};
	my $excavator_count = 0;
	my @excavators = ();
	foreach my $ship (@$avail) {
     	if($ship->{type} eq "excavator") {
     		$excavator_count++;
     		push @excavators, $ship;
     	}
     }
     ## quit without 8
     
	my $starlimit = int($excavator_count/8);
     print "$excavator_count excavators ready, targeting $starlimit stars\n";


# PREPARE THE QUERY
my $query = "SELECT * FROM stars where datetime(sentdate) < datetime('now', '-31 day') AND dist > $min_distance ORDER BY dist limit $starlimit";
my $query_handle = $db->prepare($query);

# EXECUTE THE QUERY
$query_handle->execute();

# BIND TABLE COLUMNS TO VARIABLES
my  ($sentdate, $starid, $starname, $x, $y, $dist);
$query_handle->bind_columns(\$sentdate, \$starid, \$starname, \$x, \$y, \$dist);

# LOOP THROUGH RESULTS
my $idx_excavators = 0;
my $ship;
my $rows=0;
while($query_handle->fetch() && $rows < $starlimit) {
   print "$starid, $starname, $x, $y, $dist\n";
   $rows++;

	my $orbit = 1;
	for($orbit = 1;$orbit <= 8;$orbit++) {
		$ship = $excavators[$idx_excavators++];
     	if($ship->{type} && $ship->{type} eq "excavator") {
   			print "Sending to $starname $orbit, ";
   			
			sleep 2;   			

   			my $ok = eval {
				my $targ = $space_port->send_ship($ship->{id}, {body_name => "$starname $orbit"});
				print "arrives $targ->{ship}{date_arrives} [$targ->{status}{empire}{rpc_count}]";
				return 1;
			};
			unless ($ok) {
				if (my $e = Exception::Class->caught('LacunaRPCException')) {
					if ($e->code eq '1002') {
						print "Empty orbit";
					} elsif ($e->code eq '1010') {
						print "Sent within 30 days";
					} else {
						print "$e";
					}
				}
				else {
					my $e = Exception::Class->caught();
					ref $e ? $e->rethrow : die $e;
				}
			}  
			print "\n";
		}
     }
     
    my $updatequery = "update stars set sentdate=datetime('now') where id=$starid";
	my $update_handle = $db->prepare($updatequery);
	$update_handle->execute();

# EXECUTE THE QUERY
$query_handle->execute();
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
