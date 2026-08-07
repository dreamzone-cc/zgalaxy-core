/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * (c) ZeroTier, Inc.
 * https://www.zerotier.com/
 */

#include "Topology.hpp"

#include "Buffer.hpp"
#include "Network.hpp"
#include "Node.hpp"
#include "RuntimeEnvironment.hpp"
#include "Switch.hpp"
#include "Trace.hpp"

namespace ZeroTier {

/* ZGALAXY default world (planet). Generated from the ZGALAXY planet file
 * (zgalaxy/planet.bin, via mkmoonworld): world ID 149604618, root identity
 * 069ae38092, stable endpoints 192.168.1.171/9994, dz.dreamzone.cc/9994
 * and 154.253.231.164/9994. This replaces the official ZeroTier default
 * world baked into the binary. */
#define ZT_DEFAULT_WORLD_LENGTH 271
static const unsigned char ZT_DEFAULT_WORLD[ZT_DEFAULT_WORLD_LENGTH] = {
	0x01, 0x00, 0x00, 0x00, 0x00, 0x08, 0xea, 0xc9, 0x0a, 0x00, 0x00, 0x01, 0x6c, 0xe3, 0xe2, 0x39, 0x55, 0x42, 0x21, 0xb0, 0xb1, 0x30, 0x28, 0x1c, 0xec, 0x96, 0xf9, 0xd7, 0x81, 0x66, 0x8c, 0x4d, 0x13, 0xca, 0x56, 0xcc, 0x8a, 0xcd,
	0xae, 0x83, 0xbf, 0xf1, 0xd7, 0x95, 0x72, 0x67, 0x0e, 0xcc, 0x75, 0xdc, 0xd6, 0x99, 0xc9, 0x3a, 0x0d, 0x69, 0x03, 0x21, 0x80, 0xb7, 0x55, 0x36, 0xfa, 0x67, 0x57, 0x79, 0xcf, 0x40, 0x6b, 0xaa, 0x80, 0x32, 0xd7, 0x97, 0x99, 0x06,
	0x26, 0xb2, 0xd8, 0x28, 0x3b, 0xf3, 0xe4, 0xe1, 0x75, 0xcf, 0x9e, 0x36, 0xfe, 0x4e, 0xd2, 0x6e, 0x77, 0x1e, 0xc1, 0x1a, 0xb1, 0x9b, 0x98, 0x15, 0x1e, 0xee, 0xe4, 0x6c, 0x4e, 0xfa, 0x71, 0x26, 0xea, 0x05, 0x01, 0x8c, 0x3b, 0x11,
	0x2d, 0x8b, 0x45, 0x0c, 0x04, 0x48, 0x93, 0xf0, 0xe1, 0x3b, 0x47, 0x7c, 0xf8, 0x9c, 0x6c, 0xb0, 0x05, 0xdd, 0x6d, 0x60, 0xc9, 0x20, 0x63, 0xdd, 0x98, 0x41, 0x2e, 0x98, 0x0f, 0x0f, 0x00, 0x44, 0x66, 0x5e, 0x24, 0x75, 0xe7, 0x81,
	0x20, 0x49, 0x3b, 0x3b, 0x74, 0xe5, 0x46, 0x74, 0xa6, 0x17, 0x27, 0x7f, 0x8e, 0xb0, 0xc9, 0x25, 0x7a, 0xf9, 0x5b, 0x44, 0xb6, 0xba, 0x73, 0x94, 0xa3, 0x01, 0x06, 0x9a, 0xe3, 0x80, 0x92, 0x00, 0xf2, 0x0c, 0xf7, 0x6e, 0x12, 0xea,
	0xc0, 0x2b, 0x50, 0x97, 0x8d, 0xff, 0x58, 0xd9, 0x6a, 0x97, 0x39, 0x7d, 0x88, 0x98, 0xfd, 0xe3, 0x7b, 0xc8, 0x96, 0xcd, 0x36, 0x20, 0xad, 0xf7, 0xa0, 0x64, 0x37, 0x46, 0x3f, 0x19, 0xd6, 0x3c, 0xa2, 0x6a, 0x4b, 0x23, 0xe2, 0xae,
	0x4f, 0x7e, 0x11, 0xdd, 0x25, 0xb5, 0xb3, 0x0d, 0x64, 0xed, 0x08, 0x8a, 0x0c, 0xa4, 0xfd, 0x93, 0x36, 0x19, 0xec, 0x62, 0x00, 0x03, 0x04, 0xc0, 0xa8, 0x01, 0xab, 0x27, 0x0a, 0x04, 0x00, 0x00, 0x00, 0x00, 0x27, 0x0a, 0x04, 0x9a, 0xfd, 0xe7, 0xa4, 0x27, 0x0a,
};

Topology::Topology(const RuntimeEnvironment* renv, void* tPtr) : RR(renv), _numConfiguredPhysicalPaths(0), _amUpstream(false)
{
	uint8_t tmp[ZT_WORLD_MAX_SERIALIZED_LENGTH];
	uint64_t idtmp[2];
	idtmp[0] = 0;
	idtmp[1] = 0;
	int n = RR->node->stateObjectGet(tPtr, ZT_STATE_OBJECT_PLANET, idtmp, tmp, sizeof(tmp));
	if (n > 0) {
		try {
			World cachedPlanet;
			cachedPlanet.deserialize(Buffer<ZT_WORLD_MAX_SERIALIZED_LENGTH>(tmp, (unsigned int)n), 0);
			addWorld(tPtr, cachedPlanet, false);
		}
		catch (...) {
		}	// ignore invalid cached planets
	}

	World defaultPlanet;
	{
		Buffer<ZT_DEFAULT_WORLD_LENGTH> wtmp(ZT_DEFAULT_WORLD, ZT_DEFAULT_WORLD_LENGTH);
		defaultPlanet.deserialize(wtmp, 0);	  // throws on error, which would indicate a bad static variable up top
	}
	addWorld(tPtr, defaultPlanet, false);
}

Topology::~Topology()
{
	Hashtable<Address, SharedPtr<Peer> >::Iterator i(_peers);
	Address* a = (Address*)0;
	SharedPtr<Peer>* p = (SharedPtr<Peer>*)0;
	while (i.next(a, p)) {
		_savePeer((void*)0, *p);
	}
}

SharedPtr<Peer> Topology::addPeer(void* tPtr, const SharedPtr<Peer>& peer)
{
	SharedPtr<Peer> np;
	{
		Mutex::Lock _l(_peers_m);
		SharedPtr<Peer>& hp = _peers[peer->address()];
		if (! hp) {
			hp = peer;
		}
		np = hp;
	}
	return np;
}

SharedPtr<Peer> Topology::getPeer(void* tPtr, const Address& zta)
{
	if (zta == RR->identity.address()) {
		return SharedPtr<Peer>();
	}

	{
		Mutex::Lock _l(_peers_m);
		const SharedPtr<Peer>* const ap = _peers.get(zta);
		if (ap) {
			return *ap;
		}
	}

	try {
		Buffer<ZT_PEER_MAX_SERIALIZED_STATE_SIZE> buf;
		uint64_t idbuf[2];
		idbuf[0] = zta.toInt();
		idbuf[1] = 0;
		int len = RR->node->stateObjectGet(tPtr, ZT_STATE_OBJECT_PEER, idbuf, buf.unsafeData(), ZT_PEER_MAX_SERIALIZED_STATE_SIZE);
		if (len > 0) {
			buf.setSize(len);
			Mutex::Lock _l(_peers_m);
			SharedPtr<Peer>& ap = _peers[zta];
			if (ap) {
				return ap;
			}
			ap = Peer::deserializeFromCache(RR->node->now(), tPtr, buf, RR);
			if (! ap) {
				_peers.erase(zta);
			}
			return SharedPtr<Peer>();
		}
	}
	catch (...) {
	}	// ignore invalid identities or other strange failures

	return SharedPtr<Peer>();
}

Identity Topology::getIdentity(void* tPtr, const Address& zta)
{
	if (zta == RR->identity.address()) {
		return RR->identity;
	}
	else {
		Mutex::Lock _l(_peers_m);
		const SharedPtr<Peer>* const ap = _peers.get(zta);
		if (ap) {
			return (*ap)->identity();
		}
	}
	return Identity();
}

SharedPtr<Peer> Topology::getUpstreamPeer(const uint64_t nwid)
{
	const int64_t now = RR->node->now();
	unsigned int bestq = ~((unsigned int)0);
	const SharedPtr<Peer>* best = (const SharedPtr<Peer>*)0;

	/*
	// If this is related to a network, check for a network specific relay.
	if (nwid) {
		SharedPtr<Network> network = RR->node->network(nwid);
		if (network) {
			//
		}
	}
	*/

	// If this is unrelated to a network OR there is no network-specific relay, send via a root.
	{
		Mutex::Lock _l2(_peers_m);
		Mutex::Lock _l1(_upstreams_m);
		for (std::vector<Address>::const_iterator a(_upstreamAddresses.begin()); a != _upstreamAddresses.end(); ++a) {
			const SharedPtr<Peer>* p = _peers.get(*a);
			if (p) {
				const unsigned int q = (*p)->relayQuality(now);
				if (q <= bestq) {
					bestq = q;
					best = p;
				}
			}
		}
		if (best) {
			return *best;
		}
	}

	return SharedPtr<Peer>();
}

bool Topology::isUpstream(const Identity& id) const
{
	Mutex::Lock _l(_upstreams_m);
	return (std::find(_upstreamAddresses.begin(), _upstreamAddresses.end(), id.address()) != _upstreamAddresses.end());
}

bool Topology::shouldAcceptWorldUpdateFrom(const Address& addr) const
{
	Mutex::Lock _l(_upstreams_m);
	if (std::find(_upstreamAddresses.begin(), _upstreamAddresses.end(), addr) != _upstreamAddresses.end()) {
		return true;
	}
	for (std::vector<std::pair<uint64_t, Address> >::const_iterator s(_moonSeeds.begin()); s != _moonSeeds.end(); ++s) {
		if (s->second == addr) {
			return true;
		}
	}
	return false;
}

ZT_PeerRole Topology::role(const Address& ztaddr) const
{
	Mutex::Lock _l(_upstreams_m);
	if (std::find(_upstreamAddresses.begin(), _upstreamAddresses.end(), ztaddr) != _upstreamAddresses.end()) {
		for (std::vector<World::Root>::const_iterator i(_planet.roots().begin()); i != _planet.roots().end(); ++i) {
			if (i->identity.address() == ztaddr) {
				return ZT_PEER_ROLE_PLANET;
			}
		}
		return ZT_PEER_ROLE_MOON;
	}
	return ZT_PEER_ROLE_LEAF;
}

bool Topology::isProhibitedEndpoint(const Address& ztaddr, const InetAddress& ipaddr) const
{
	Mutex::Lock _l(_upstreams_m);

	// For roots the only permitted addresses are those defined. This adds just a little
	// bit of extra security against spoofing, replaying, etc.
	if (std::find(_upstreamAddresses.begin(), _upstreamAddresses.end(), ztaddr) != _upstreamAddresses.end()) {
		for (std::vector<World::Root>::const_iterator r(_planet.roots().begin()); r != _planet.roots().end(); ++r) {
			if (r->identity.address() == ztaddr) {
				if (r->stableEndpoints.empty()) {
					return false;	// no stable endpoints specified, so allow dynamic paths
				}
				for (std::vector<InetAddress>::const_iterator e(r->stableEndpoints.begin()); e != r->stableEndpoints.end(); ++e) {
					if (ipaddr.ipsEqual(*e)) {
						return false;
					}
				}
			}
		}
		for (std::vector<World>::const_iterator m(_moons.begin()); m != _moons.end(); ++m) {
			for (std::vector<World::Root>::const_iterator r(m->roots().begin()); r != m->roots().end(); ++r) {
				if (r->identity.address() == ztaddr) {
					if (r->stableEndpoints.empty()) {
						return false;	// no stable endpoints specified, so allow dynamic paths
					}
					for (std::vector<InetAddress>::const_iterator e(r->stableEndpoints.begin()); e != r->stableEndpoints.end(); ++e) {
						if (ipaddr.ipsEqual(*e)) {
							return false;
						}
					}
				}
			}
		}
		return true;
	}

	return false;
}

void Topology::getRootsToContact(Hashtable<Address, std::vector<InetAddress> >& eps) const
{
	Mutex::Lock _l(_upstreams_m);

	for (std::vector<World::Root>::const_iterator i(_planet.roots().begin()); i != _planet.roots().end(); ++i) {
		if (i->identity != RR->identity) {
			std::vector<InetAddress>& ips = eps[i->identity.address()];
			for (std::vector<InetAddress>::const_iterator j(i->stableEndpoints.begin()); j != i->stableEndpoints.end(); ++j) {
				if (std::find(ips.begin(), ips.end(), *j) == ips.end()) {
					ips.push_back(*j);
				}
			}
		}
	}

	for (std::vector<World>::const_iterator m(_moons.begin()); m != _moons.end(); ++m) {
		for (std::vector<World::Root>::const_iterator i(m->roots().begin()); i != m->roots().end(); ++i) {
			if (i->identity != RR->identity) {
				std::vector<InetAddress>& ips = eps[i->identity.address()];
				for (std::vector<InetAddress>::const_iterator j(i->stableEndpoints.begin()); j != i->stableEndpoints.end(); ++j) {
					if (std::find(ips.begin(), ips.end(), *j) == ips.end()) {
						ips.push_back(*j);
					}
				}
			}
		}
	}
	for (std::vector<std::pair<uint64_t, Address> >::const_iterator m(_moonSeeds.begin()); m != _moonSeeds.end(); ++m) {
		eps[m->second];
	}
}

bool Topology::addWorld(void* tPtr, const World& newWorld, bool alwaysAcceptNew)
{
	if ((newWorld.type() != World::TYPE_PLANET) && (newWorld.type() != World::TYPE_MOON)) {
		return false;
	}

	Mutex::Lock _l2(_peers_m);
	Mutex::Lock _l1(_upstreams_m);

	World* existing = (World*)0;
	switch (newWorld.type()) {
		case World::TYPE_PLANET:
			existing = &_planet;
			break;
		case World::TYPE_MOON:
			for (std::vector<World>::iterator m(_moons.begin()); m != _moons.end(); ++m) {
				if (m->id() == newWorld.id()) {
					existing = &(*m);
					break;
				}
			}
			break;
		default:
			return false;
	}

	if (existing) {
		if (existing->shouldBeReplacedBy(newWorld)) {
			*existing = newWorld;
		}
		else {
			return false;
		}
	}
	else if (newWorld.type() == World::TYPE_MOON) {
		if (alwaysAcceptNew) {
			_moons.push_back(newWorld);
			existing = &(_moons.back());
		}
		else {
			for (std::vector<std::pair<uint64_t, Address> >::iterator m(_moonSeeds.begin()); m != _moonSeeds.end(); ++m) {
				if (m->first == newWorld.id()) {
					for (std::vector<World::Root>::const_iterator r(newWorld.roots().begin()); r != newWorld.roots().end(); ++r) {
						if (r->identity.address() == m->second) {
							_moonSeeds.erase(m);
							_moons.push_back(newWorld);
							existing = &(_moons.back());
							break;
						}
					}
					if (existing) {
						break;
					}
				}
			}
		}
		if (! existing) {
			return false;
		}
	}
	else {
		return false;
	}

	try {
		Buffer<ZT_WORLD_MAX_SERIALIZED_LENGTH> sbuf;
		existing->serialize(sbuf, false);
		uint64_t idtmp[2];
		idtmp[0] = existing->id();
		idtmp[1] = 0;
		RR->node->stateObjectPut(tPtr, (existing->type() == World::TYPE_PLANET) ? ZT_STATE_OBJECT_PLANET : ZT_STATE_OBJECT_MOON, idtmp, sbuf.data(), sbuf.size());
	}
	catch (...) {
	}

	_memoizeUpstreams(tPtr);

	return true;
}

void Topology::addMoon(void* tPtr, const uint64_t id, const Address& seed)
{
	char tmp[ZT_WORLD_MAX_SERIALIZED_LENGTH];
	uint64_t idtmp[2];
	idtmp[0] = id;
	idtmp[1] = 0;
	int n = RR->node->stateObjectGet(tPtr, ZT_STATE_OBJECT_MOON, idtmp, tmp, sizeof(tmp));
	if (n > 0) {
		try {
			World w;
			w.deserialize(Buffer<ZT_WORLD_MAX_SERIALIZED_LENGTH>(tmp, (unsigned int)n));
			if ((w.type() == World::TYPE_MOON) && (w.id() == id)) {
				addWorld(tPtr, w, true);
				return;
			}
		}
		catch (...) {
		}
	}

	if (seed) {
		Mutex::Lock _l(_upstreams_m);
		if (std::find(_moonSeeds.begin(), _moonSeeds.end(), std::pair<uint64_t, Address>(id, seed)) == _moonSeeds.end()) {
			_moonSeeds.push_back(std::pair<uint64_t, Address>(id, seed));
		}
	}
}

void Topology::removeMoon(void* tPtr, const uint64_t id)
{
	Mutex::Lock _l2(_peers_m);
	Mutex::Lock _l1(_upstreams_m);

	std::vector<World> nm;
	for (std::vector<World>::const_iterator m(_moons.begin()); m != _moons.end(); ++m) {
		if (m->id() != id) {
			nm.push_back(*m);
		}
		else {
			uint64_t idtmp[2];
			idtmp[0] = id;
			idtmp[1] = 0;
			RR->node->stateObjectDelete(tPtr, ZT_STATE_OBJECT_MOON, idtmp);
		}
	}
	_moons.swap(nm);

	std::vector<std::pair<uint64_t, Address> > cm;
	for (std::vector<std::pair<uint64_t, Address> >::const_iterator m(_moonSeeds.begin()); m != _moonSeeds.end(); ++m) {
		if (m->first != id) {
			cm.push_back(*m);
		}
	}
	_moonSeeds.swap(cm);

	_memoizeUpstreams(tPtr);
}

void Topology::doPeriodicTasks(void* tPtr, int64_t now)
{
	{
		Mutex::Lock _l1(_peers_m);
		Mutex::Lock _l2(_upstreams_m);
		Hashtable<Address, SharedPtr<Peer> >::Iterator i(_peers);
		Address* a = (Address*)0;
		SharedPtr<Peer>* p = (SharedPtr<Peer>*)0;
		while (i.next(a, p)) {
			if ((! (*p)->isAlive(now)) && (std::find(_upstreamAddresses.begin(), _upstreamAddresses.end(), *a) == _upstreamAddresses.end())) {
				_savePeer(tPtr, *p);
				_peers.erase(*a);
			}
		}
	}

	{
		Mutex::Lock _l(_paths_m);
		Hashtable<Path::HashKey, SharedPtr<Path> >::Iterator i(_paths);
		Path::HashKey* k = (Path::HashKey*)0;
		SharedPtr<Path>* p = (SharedPtr<Path>*)0;
		while (i.next(k, p)) {
			if (p->references() <= 1) {
				_paths.erase(*k);
			}
		}
	}
}

void Topology::_memoizeUpstreams(void* tPtr)
{
	// assumes _upstreams_m and _peers_m are locked
	_upstreamAddresses.clear();
	_amUpstream = false;

	for (std::vector<World::Root>::const_iterator i(_planet.roots().begin()); i != _planet.roots().end(); ++i) {
		const Identity& id = i->identity;
		if (id == RR->identity) {
			_amUpstream = true;
		}
		else if (std::find(_upstreamAddresses.begin(), _upstreamAddresses.end(), id.address()) == _upstreamAddresses.end()) {
			_upstreamAddresses.push_back(id.address());
			SharedPtr<Peer>& hp = _peers[id.address()];
			if (! hp) {
				hp = new Peer(RR, RR->identity, id);
			}
		}
	}

	for (std::vector<World>::const_iterator m(_moons.begin()); m != _moons.end(); ++m) {
		for (std::vector<World::Root>::const_iterator i(m->roots().begin()); i != m->roots().end(); ++i) {
			if (i->identity == RR->identity) {
				_amUpstream = true;
			}
			else if (std::find(_upstreamAddresses.begin(), _upstreamAddresses.end(), i->identity.address()) == _upstreamAddresses.end()) {
				_upstreamAddresses.push_back(i->identity.address());
				SharedPtr<Peer>& hp = _peers[i->identity.address()];
				if (! hp) {
					hp = new Peer(RR, RR->identity, i->identity);
				}
			}
		}
	}

	std::sort(_upstreamAddresses.begin(), _upstreamAddresses.end());
}

void Topology::_savePeer(void* tPtr, const SharedPtr<Peer>& peer)
{
	try {
		Buffer<ZT_PEER_MAX_SERIALIZED_STATE_SIZE> buf;
		peer->serializeForCache(buf);
		uint64_t tmpid[2];
		tmpid[0] = peer->address().toInt();
		tmpid[1] = 0;
		RR->node->stateObjectPut(tPtr, ZT_STATE_OBJECT_PEER, tmpid, buf.data(), buf.size());
	}
	catch (...) {
	}	// sanity check, discard invalid entries
}

}	// namespace ZeroTier
