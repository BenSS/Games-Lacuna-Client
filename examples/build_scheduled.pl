use strict;
use warnings;
use Games::Lacuna::Client;
use Data::Dumper;
use Getopt::Long qw(GetOptions);

use constant MINUTE => 60;

our $TimePerIteration = 20;

GetOptions(
  'i|interval=f' => \$TimePerIteration,
);
$TimePerIteration = int($TimePerIteration * MINUTE);

my $config_file = shift @ARGV;
if (not defined $config_file or not -e $config_file) {
  die "Usage: $0 myempire.yml";
}

my $client = Games::Lacuna::Client->new(
  cfg_file => $config_file,
  #debug => 1,
);

my %to_be_built = (
  colony_ship => {
    planet => 'mehplanet1',
    x => 2,
    y => -1,
    ship_type => 'short_range_colony_ship',
    building => $client->building(type => 'Shipyard'),
    dependent_on => [qw()],
    #dependent_on => [qw(shipyard)],
  },
  #shipyard => {
  #  planet => 'mehplanet1',
  #  x => 2,
  #  y => -1,
  #  upgrade => 1,
  #  building => $client->building(type => 'Shipyard'),
  #  dependent_on => [qw()],
  #},
);

my @work_order = build_topo_sort(%to_be_built);

my $empire = $client->empire;
my $estatus = $empire->get_status->{empire};
my %planets_by_name = map { ($estatus->{planets}->{$_} => $client->body(id => $_)) }
                      keys %{$estatus->{planets}};


my %failed_jobs;
while (1) {
  output("Checking status");

  my %tainted_planets;
  my %checked_planets;
  die if not @work_order;
  my $current_work = $work_order[0];
  output("Current work slice: " . join (", ", @$current_work));

  foreach (my $ibuild = 0; $ibuild < @$current_work; ++$ibuild) {
    my $name = $current_work->[$ibuild];
    my $build_order = $to_be_built{$name};
    output("Attempting '$name'");

    # check for bad dependencies
    if (grep {$failed_jobs{$_}} @{$build_order->{dependent_on}}) {
      output("Depends on failed job. Removing.");
      $failed_jobs{$name} = 1;
      splice(@$current_work, $ibuild, 1);
      $ibuild--;
      next;
    }
    # check for known (currently) bad planets
    if ($tainted_planets{ $build_order->{planet} }) {
      output("Planet busy, skipping.");
      next;
    }

    my $planet_name = $build_order->{planet};
    my $planet = $planets_by_name{$planet_name};

    if (not $checked_planets{$planet_name}) {
      # This needs better API (understanding)
      #my $buildable = $planet->get_buildable(0, 0, 'Storage');
      #if ($buildable->{build_queue}{max} <= $buildable->{build_queue}{current}) {
      #  output("Planet build queue is full. Marking as tainted. Skipping.");
      #  $tainted_planets{$planet_name} = 1;
      #  next;
      #}
      my $buildings_struct = $planet->get_buildings();
      $checked_planets{$planet_name} = $buildings_struct;
    }

    if (not defined $build_order->{building}->building_id) {
      $build_order->{building}->{building_id} = find_building_id($checked_planets{$planet_name}, $build_order->{x}, $build_order->{y});
    }

    my $err;
    my $action;
    if ($build_order->{ship_type}) {
      output("Building new ship");
      $action = 'ship';
      eval { $build_order->{building}->build_ship($build_order->{ship_type}) };
      $err = $@;
    }
    elsif ($build_order->{upgrade}) {
      output("Performing upgrade of building.");
      $action = 'upgrade';
      eval { $build_order->{building}->upgrade() };
      $err = $@;
    }
    else { # fresh build
      output("Constructing new building");
      $action = 'build';
      eval { $build_order->{building}->build($planet->body_id, $build_order->{x}, $build_order->{y}) };
      $err = $@;
    } # end fresh build

    if ($err) {
      output(ucfirst($action) . " failed.");
      $err =~ /^RPC Error \((\d+)\)/ or die $err;
      my $code = $1;
      if ($code == 1009) { # not specified but probably what happens when building on another building
        if ($action eq 'build') {
          output("Space is (probably) occupied ($err). Removing.");
          splice(@$current_work, $ibuild, 1);
          $ibuild--;
          next;
        }
        else {
          die $err;
        }
      }
      if ($code == 1010) { # no privs
        output("Not enough priviledges ($err). Removing.");
        splice(@$current_work, $ibuild, 1);
        $ibuild--;
        next;
      }
      if ($code == 1002) { # no privs
        output("Bad object ($err). Removing.");
        splice(@$current_work, $ibuild, 1);
        $ibuild--;
        next;
      }
      elsif ($code == 1011 or $code == 1012 or $code == 1013) { next; } # not yet
      else { die $err; }
    } # end if action failed
    else {
      output("Sucessfully performed $action. Removing.");
      splice(@$current_work, $ibuild, 1);
      $ibuild--;
      next;
    } # end action was successful

  } # end foreach build order

  # done with this level of dependencies
  if (not @$current_work) {
    output("Done with current work unit");
    shift @work_order;
    if (not @work_order) {
      output("Done! Exiting.");
      last;
    }
    next;
  }
 
  output("Waiting for next iteration");
  sleep $TimePerIteration;
}

sub output {
  my $str = join ' ', @_;
  $str .= "\n" if $str !~ /\n$/;
  print "[" . localtime() . "] " . $str;
}


sub build_topo_sort {
    my %obj = @_;

    my @independent;
    my %deps;
    foreach my $name (keys %obj) {
      $deps{$name} = [@{$obj{$name}{dependent_on}}];
      if (not @{$deps{$name}}) {
        push @independent, $name;
      }
    }
 
    my %ba;
    while ( my ( $before, $afters_aref ) = each %deps ) {
        for my $after ( @{ $afters_aref } ) {
            $ba{$before}{$after} = 1 if $before ne $after;
            $ba{$after} ||= {};
        }
    }

    my @res;
    while ( my @afters = sort grep { ! %{ $ba{$_} } } keys %ba ) {
        push @res, [@afters];
        delete @ba{@afters};
        delete @{$_}{@afters} for values %ba;
    }
 
    if (keys %ba) {
      die "Cycle found: " . join(' ', sort keys %ba);
    }
    if (not @res) {
      push @res, \@independent;
    }
    else {
      push @{$res[0]}, \@independent;
    }

    return @res;
}

sub find_building_id {
  my $struct = shift;
  my $x = shift;
  my $y = shift;

  my $b = $struct->{buildings};
  foreach my $id (keys %$b) {
    if ($b->{$id}{x} == $x and $b->{$id}{y} == $y) {
      return $id;
    }
  }
  return();
}