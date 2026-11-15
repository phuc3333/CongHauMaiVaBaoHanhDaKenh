package haumai.contract;

/** Names of Redis Streams shared between channel-gateway and warranty-core. */
public final class ChannelStreams {
    public static final String INBOUND_REQUESTS = "warranty:inbound";
    public static final String INBOUND_REPLIES = "warranty:inbound:replies";
    public static final String OUTBOUND_REQUESTS = "warranty:outbound";
    public static final String OUTBOUND_RESULTS = "warranty:outbound:results";

    private ChannelStreams() {
    }
}
