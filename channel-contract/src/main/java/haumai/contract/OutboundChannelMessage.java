package haumai.contract;

public record OutboundChannelMessage(
    Long tinNhanId,
    String maKenh,
    String maNguoiDungKenh,
    String noiDung,
    Long tinNhanCuocTroChuyenId
) {
    public OutboundChannelMessage(Long tinNhanId, String maKenh, String maNguoiDungKenh, String noiDung) {
        this(tinNhanId, maKenh, maNguoiDungKenh, noiDung, null);
    }
}
