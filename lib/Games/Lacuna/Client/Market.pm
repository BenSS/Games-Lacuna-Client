package Games::Lacuna::Client::Market;
use strict;
use warnings;

use Games::Lacuna::Client;
use Scalar::Util qw'blessed';

our @opt = qw{
  call_limit
  building
  planet_id
  planet_name
};

sub new{
  my($class,%opt) = @_;
  $class = blessed $class || $class;

  my $client = Games::Lacuna::Client->new(
    %opt
  );

  my $self = bless {
    client => $client,
    call_limit => 20,
  }, $class;

  @$self{@opt} = @opt{@opt};

  return $self;
}

sub _args{
  my($self,$wanted,$args) = @_;
  my %return;
  for my $arg(@$wanted){
    if( $args->{$arg} ){
      $return{$arg} = $args->{$arg};
    }elsif( $self->{$arg} ){
      $return{$arg} = $self->{$arg};
    }
  }
  return %return if wantarray;
  return \%return;
}

sub _search_for_building{
  my($self,$pid,$type) = @_;
  # $type should be Trade or Transporter
  $type = 'Trade' unless $type;
  $type = "/$type" unless substr($type, 0, 1) eq '/';
  $type = lc $type;

  my $buildings = $self->{client}->body(id => $pid)->get_buildings()->{buildings};

  for my $id ( keys %$buildings ){
    my $url = $buildings->{$id}{url};
    next unless $url eq $type;
    return $id;
  }

  return undef; # should this die instead?
}

sub available_trades{
  my($self,%arg) = @_;
  my $client = $self->{client};
  my $status = $client->empire->get_status();
  my $planets = $status->{empire}{planets};
  my $home = $status->{empire}{home_planet_id};

  %arg = $self->_args([qw'planet_id planet_name call_limit building'],\%arg);

  my $p_id;
  if( $arg{planet_name} and not $arg{planet_id} ){
    my $planet = $arg{planet_name};
    ($p_id) = grep { $planets->{$_} eq $planet } keys %$planets;
  }elsif( $arg{planet_id} ){
    $p_id = $arg{planet_id};
  }

  my $type = $arg{building};
  # $type should be Trade or Transporter
  $type = 'Trade' unless $type;
  my($class,%opt) = @_;
  $class = blessed $class || $class;

  my $b_id;

  if( defined $p_id ){
    $b_id = $self->_search_for_building($p_id,$type);
  }else{
    for $p_id ( keys %$planets ){
      $b_id = $self->_search_for_building($p_id,$type);
      last if $b_id;
    }
  }

  die "Unable to find appropriate building" unless $b_id;

  my $building = $client->building( id => $b_id, type => $type );
  my $page_num = 1;
  my $trades_per_page = 25;
  my $max_pages = $arg{call_limit} || 20;
  my $trade_count;
  my @trades;

  while ($page_num <= $max_pages and (not defined $trade_count
   or $trade_count > ($page_num * $trades_per_page ))) {
      my $result = $building->view_market($page_num);
      $page_num++;
      $trade_count = $result->{trade_count};
      push @trades, map{
        Games::Lacuna::Client::Market::Trade->new($_,$type);
      } @{$result->{trades}};
  }

  return @trades if wantarray;
  return \@trades;
}


{
  package Games::Lacuna::Client::Market::Trade;
  use Scalar::Util qw'blessed';

  sub new{
    my($class,$trade,$type) = @_;
    $class = blessed $class || $class;

    my $self = bless $trade, $class;
    $trade->{type} = $type;

    my @offer = map {
      Games::Lacuna::Client::Market::Trade::Item->new($_)
    } @{$trade->{offer}};

    $trade->{offer} = \@offer;

    return $self;
  }
  sub ask{
    my($self) = @_;
    return $self->{ask};
  }
  sub cost{
    # Asking price plus Transporter "tax"
    my($self) = @_;
    my $cost = $self->ask;
    if( $self->{type} eq 'Transporter' ){
      $cost++;
    }
    return $cost;
  }
  sub offer{
    my($self) = @_;
    my @offer = @{$self->{offer}};
    return @offer if wantarray;
    return \@offer;
  }
  sub size{
    my($self) = @_;
    my $size = 0;
    for my $offer ( $self->offer ){
      $size += $offer->size;
    }
    return $size;
  }
  sub empire{
    my($self) = @_;
    return $self->{empire}{name}
  }
  sub empire_id{
    my($self) = @_;
    return $self->{empire}{id}
  }
}
{
  package Games::Lacuna::Client::Market::Trade::Item;

  sub new{
    my($class,$item) = @_;

    my $self = \$item;
    if( $item =~ /^(.*?)\s+\(.*?\)$/ ){
      bless $self, 'Games::Lacuna::Client::Market::Trade::Ship';
    }elsif( $item =~ /\bglyph$/ ){
      bless $self, 'Games::Lacuna::Client::Market::Trade::Glyph';
    }elsif( $item =~ /\bplan$/ ){
      bless $self, 'Games::Lacuna::Client::Market::Trade::Plan';
    }else{
      bless $self, 'Games::Lacuna::Client::Market::Trade::SimpleItem';
    }
    return $self;
  }
}
{
  package Games::Lacuna::Client::Market::Trade::SimpleItem;
  use Games::Lacuna::Client::Types ':list';
  use List::MoreUtils qw'any';

  sub type{
    my($self) = @_;
    my $type;
    if( ($type) = $$self =~ m(\s(\w+)$) ){
      if( any { $_ eq $type } food_types() ){
        return 'food';
      }elsif( any { $_ eq $type } ore_types() ){
        return 'ore';
      }elsif( any { $_ eq $type } qw'waste water energy glyph plan' ){
        return $type;
      }
    }elsif( ($type) = $$self =~ /^([\w-]+) / ){
      if( $$self =~ /^(?:spy|prisoner)/i ){
        return 'prisoner';
      }
    }

    return;
  }

  sub size{
    my($self) = @_;
    my($amount) = $$self =~ /(.*)\s/;
    $amount =~ s/,//;
    return $amount;
  }
  
  sub desc{
    my($self) = @_;
    return $$self;
  }
}
{
  package Games::Lacuna::Client::Market::Trade::Plan;
  our @ISA = 'Games::Lacuna::Client::Market::Trade::SimpleItem';

  sub size{ return 10_000 }
}
{
  package Games::Lacuna::Client::Market::Trade::Glyph;
  our @ISA = 'Games::Lacuna::Client::Market::Trade::SimpleItem';

  sub size{ return 100 }
}
{
  package Games::Lacuna::Client::Market::Trade::Ship;
  our @ISA = 'Games::Lacuna::Client::Market::Trade::SimpleItem';

  sub type{ return 'ship' }
  sub size{ return 50_000 }

  sub ship_type{
    my($self) = @_;
    my($type) = $$self =~ /^([^\(]+?) \(.*\)/;
    return $type;
  }

  sub info{
    my($self) = @_;
    my($data) = $$self =~ /\((.*)\)/;

    my %data = split /[,:] /, $data;
    s/,// for values %data;

    return %data if wantarray;
    return \%data;
  }
  sub speed{
    my($self) = @_;
    return $self->info->{speed}
  }
  sub stealth{
    my($self) = @_;
    return $self->info->{stealth}
  }
  sub hold_size{
    my($self) = @_;
    return $self->info->{'hold size'}
  }
  sub combat{
    my($self) = @_;
    return $self->info->{combat}
  }
}
1;
